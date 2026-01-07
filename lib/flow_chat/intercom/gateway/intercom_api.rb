require "json"
require "openssl"

module FlowChat
  module Intercom
    # Configuration-related errors
    class ConfigurationError < StandardError; end

    module Gateway
      class IntercomApi
        include FlowChat::Instrumentation
        include FlowChat::GatewayAsyncSupport

        attr_reader :client

        # Default webhook topics to process
        DEFAULT_WEBHOOK_TOPICS = ["conversation.user.created", "conversation.user.replied"].freeze

        def initialize(app, config = nil, additional_webhook_topics = nil)
          @app = app
          @config = config || FlowChat::Intercom::Configuration.from_credentials
          @client = FlowChat::Intercom::Client.new(@config)
          # Always include default topics, plus any additional ones
          @allowed_webhook_topics = DEFAULT_WEBHOOK_TOPICS + Array(additional_webhook_topics)

          FlowChat.logger.info { "IntercomApi: Initialized Intercom API gateway" }
          FlowChat.logger.debug { "IntercomApi: Gateway configuration - API base URL: #{@config.api_base_url}" }
          FlowChat.logger.debug { "IntercomApi: Allowed webhook topics: #{@allowed_webhook_topics.inspect}" }
        end

        def call(context)
          @context = context
          @controller = context.controller
          request = @controller.request

          FlowChat.logger.debug { "IntercomApi: Processing #{request.request_method} request to #{request.path}" }

          # Skip webhook-specific handling in background mode
          unless in_background?
            # Handle webhook URL validation (HEAD request)
            if request.head?
              FlowChat.logger.info { "IntercomApi: Handling webhook URL validation request" }
              return @controller.head :ok
            end
          end

          # Handle webhook notifications (POST request)
          if request.post?
            FlowChat.logger.info { "IntercomApi: Handling webhook notification (background: #{in_background?})" }
            return handle_webhook(context)
          end

          FlowChat.logger.warn { "IntercomApi: Invalid request method or parameters - returning bad request" }
          @controller.head :bad_request
        end

        private

        def handle_webhook(context)
          # Parse body
          begin
            parse_request_body(@controller.request)
            FlowChat.logger.debug { "IntercomApi: Successfully parsed webhook request body" }
          rescue JSON::ParserError => e
            FlowChat.logger.error { "IntercomApi: Failed to parse webhook body: #{e.message}" }
            return @controller.head :bad_request
          end

          # Check for simulator mode parameter in request (before validation)
          # But only enable if valid simulator token is provided
          is_simulator_mode = simulate?(context)
          if is_simulator_mode
            FlowChat.logger.info { "IntercomApi: Simulator mode enabled for this request" }
            context["simulator_mode"] = true
          end

          # Validate webhook signature for security (skip for simulator mode and background)
          unless in_background? || is_simulator_mode || valid_webhook_signature?(@controller.request)
            FlowChat.logger.warn { "IntercomApi: Invalid webhook signature received - rejecting request" }
            return @controller.head :unauthorized
          end

          FlowChat.logger.debug { "IntercomApi: Webhook signature validation passed" }

          # Extract event data from Intercom webhook
          event_type = @body["topic"]
          unless event_type
            FlowChat.logger.debug { "IntercomApi: No topic found in webhook body - returning OK" }
            return @controller.head :ok
          end

          # Only process conversation events we care about
          unless @allowed_webhook_topics.include?(event_type)
            FlowChat.logger.debug { "IntercomApi: Ignoring event type '#{event_type}' (not in allowed topics) - returning OK" }
            return @controller.head :ok
          end

          # Extract conversation data
          data_item = @body.dig("data", "item")
          unless data_item
            FlowChat.logger.debug { "IntercomApi: No data.item found in webhook body - returning OK" }
            return @controller.head :ok
          end

          # Process conversation event
          if data_item["type"] == "conversation"
            conversation = data_item
            conversation_id = conversation["id"]

            # Get the user ID from contacts (always the actual user/contact)
            # contacts.contacts[0] contains the actual user, not the admin
            contact = conversation.dig("contacts", "contacts", 0)
            unless contact
              FlowChat.logger.error { "IntercomApi: No contact found in conversation" }
              return @controller.head :ok
            end

            # Get user ID from contact (most reliable)
            user_id = contact["id"]

            context["request.id"] = conversation_id
            context["request.user_id"] = user_id
            context["request.gateway"] = :intercom_api
            context["request.platform"] = :intercom
            context["request.timestamp"] = Time.now.iso8601
            context["request.body"] = @body

            context["intercom.client"] = @client
            context["intercom.topic"] = event_type

            # Try to extract latest message for user events
            latest_message = extract_latest_user_message(conversation, event_type)

            if latest_message
              context["request.message_id"] = latest_message[:id]
              # Strip HTML tags from message body
              raw_body = latest_message[:body] || ""
              context.input = raw_body.gsub(/<[^>]*>/, "").strip.presence || ""
              FlowChat.logger.debug { "IntercomApi: Message content extracted - Event: #{event_type}, Input: '#{context.input}'" }
            elsif @allowed_webhook_topics.include?(event_type)
              # No message but event is explicitly allowed - process without message
              context.input = nil
              FlowChat.logger.debug { "IntercomApi: Processing #{event_type} event without user message" }
            else
              # No message and event not in allowed topics - skip
              # (This case shouldn't happen as we already filtered above, but safety check)
              FlowChat.logger.error { "IntercomApi: No message found for unexpected event type '#{event_type}'" }
              return @controller.head :ok
            end

            # Instrument message received (with or without message content)
            instrument(Events::MESSAGE_RECEIVED, {
              from: user_id,
              conversation_id: conversation_id,
              message: context.input,
              event_type: event_type
            })

            # Determine routing: async enqueue, background execute, or inline
            if should_enqueue_async?
              # Webhook with async enabled → enqueue job and return immediately
              enqueue_async_job
              return @controller.head :ok
            else
              # Background OR inline → process message
              # Determine message handling mode (simulator vs inline)
              handler_mode = determine_message_handler(context)

              # Process the message based on handling mode
              case handler_mode
              when :inline
                handle_message_inline(context, @controller)
              when :simulator
                # Return early from simulator mode to preserve the JSON response
                return handle_message_simulator(context, @controller)
              end
            end
          end

          @controller.head :ok
        end

        def determine_message_handler(context)
          # Use simulator mode if enabled, otherwise always use inline
          if context["simulator_mode"]
            FlowChat.logger.debug { "IntercomApi: Using simulator message handler" }
            :simulator
          else
            FlowChat.logger.debug { "IntercomApi: Using inline message handler" }
            :inline
          end
        end

        # Validate webhook signature to ensure request comes from Intercom
        def valid_webhook_signature?(request)
          # Check if signature validation is explicitly disabled
          if @config.skip_signature_validation
            FlowChat.logger.debug { "IntercomApi: Webhook signature validation is disabled" }
            return true
          end

          # Require client_secret for signature validation
          unless @config.client_secret && !@config.client_secret.empty?
            error_msg = "Intercom client_secret is required for webhook signature validation. " \
                       "Either configure client_secret or set skip_signature_validation=true to explicitly disable validation."
            FlowChat.logger.error { "IntercomApi: #{error_msg}" }
            raise FlowChat::Intercom::ConfigurationError, error_msg
          end

          signature_header = request.headers["X-Hub-Signature"]
          unless signature_header
            FlowChat.logger.warn { "IntercomApi: No X-Hub-Signature header found in request" }
            return false
          end

          # Extract signature from header (format: "sha1=<signature>")
          expected_signature = signature_header.sub("sha1=", "")

          # Get raw request body
          request.body.rewind
          body = request.body.read
          request.body.rewind

          # Calculate HMAC signature using SHA1 (Intercom uses SHA1, not SHA256)
          calculated_signature = OpenSSL::HMAC.hexdigest(
            OpenSSL::Digest.new("sha1"),
            @config.client_secret,
            body
          )

          # Compare signatures using secure comparison to prevent timing attacks
          signature_valid = secure_compare(expected_signature, calculated_signature)

          if signature_valid
            FlowChat.logger.debug { "IntercomApi: Webhook signature validation successful" }
          else
            FlowChat.logger.warn { "IntercomApi: Webhook signature validation failed - signatures do not match" }
          end

          signature_valid
        rescue FlowChat::Intercom::ConfigurationError
          raise
        rescue => e
          FlowChat.logger.error { "IntercomApi: Error validating webhook signature: #{e.class.name}: #{e.message}" }
          false
        end

        # Secure string comparison to prevent timing attacks
        def secure_compare(a, b)
          return false unless a.bytesize == b.bytesize

          l = a.unpack("C*")
          res = 0
          b.each_byte { |byte| res |= byte ^ l.shift }
          res == 0
        end

        def extract_latest_user_message(conversation, event_type)
          FlowChat.logger.debug { "IntercomApi: Extracting latest user message from #{event_type} event" }

          case event_type
          when "conversation.user.created"
            # For new conversations, get the initial message from source
            source = conversation["source"]
            if source && source["body"]
              {
                id: source["id"],
                body: source["body"]
              }
            end
          when "conversation.user.replied"
            # For replies, get the latest user message from conversation_parts
            parts = conversation.dig("conversation_parts", "conversation_parts") || []

            # Find the most recent part from a user (not admin)
            # Note: user type can be "user", "lead", or "contact"
            user_parts = parts.select do |part|
              part["part_type"] == "comment" &&
                %w[user lead contact].include?(part.dig("author", "type"))
            end

            if user_parts.any?
              latest_part = user_parts.last
              {
                id: latest_part["id"],
                body: latest_part["body"]
              }
            end
          end
        end

        def handle_message_inline(context, controller)
          response = @app.call(context)
          if response
            _type, prompt, choices, media = response
            result = @client.send_message(context["request.id"], prompt, choices: choices, media: media)
            context["intercom.message_result"] = result

            # Instrument message sent
            instrument(Events::MESSAGE_SENT, {
              to: context["request.user_id"],
              conversation_id: context["request.id"],
              message: prompt,
              gateway: :intercom_api,
              platform: :intercom,
              content_length: prompt.to_s.length,
              timestamp: context["request.timestamp"]
            })
          end
        end

        def handle_message_simulator(context, controller)
          response = @app.call(context)

          if response
            _type, prompt, choices, media = response
            rendered_message = render_response(prompt, choices, media)

            # For simulator mode, return the response data in the HTTP response
            # instead of actually sending via Intercom API
            message_payload = @client.build_reply_payload(rendered_message, context["request.id"])

            simulator_response = {
              mode: "simulator",
              webhook_processed: true,
              would_send: message_payload,
              message_info: {
                to: context["request.id"],
                user_id: context["request.user_id"],
                timestamp: Time.now.iso8601
              }
            }

            @controller.render json: simulator_response
            nil
          end
        end

        def simulate?(context)
          # Check if simulator mode is enabled for this processor
          return false unless context["enable_simulator"]

          # Then check if simulator mode is requested and valid
          @body.dig("simulator_mode") && valid_simulator_cookie?(context)
        end

        def valid_simulator_cookie?(context)
          simulator_secret = FlowChat::Config.simulator_secret
          return false unless simulator_secret && !simulator_secret.empty?

          # Check for simulator cookie
          simulator_cookie = @controller.request.cookies["flowchat_simulator"]
          return false unless simulator_cookie

          # Verify the cookie is a valid HMAC signature
          # Cookie format: "timestamp:signature" where signature = HMAC(simulator_secret, "simulator:timestamp")
          begin
            timestamp_str, signature = simulator_cookie.split(":", 2)
            return false unless timestamp_str && signature

            # Check timestamp is recent (within 24 hours for reasonable session duration)
            timestamp = timestamp_str.to_i
            return false if timestamp <= 0
            return false if (Time.now.to_i - timestamp).abs > 86400 # 24 hours

            # Calculate expected signature
            message = "simulator:#{timestamp_str}"
            expected_signature = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), simulator_secret, message)

            # Use secure comparison
            secure_compare(signature, expected_signature)
          rescue => e
            Rails.logger.warn "Invalid simulator cookie format: #{e.message}"
            false
          end
        end

        def parse_request_body(request)
          @body ||= JSON.parse(request.body.read)
        end

        def render_response(prompt, choices, media)
          FlowChat::Intercom::Renderer.new(prompt, choices: choices, media: media).render
        end
      end
    end
  end
end

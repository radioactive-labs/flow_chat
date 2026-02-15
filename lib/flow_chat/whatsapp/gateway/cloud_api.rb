require "net/http"
require "json"
require "openssl"

module FlowChat
  module Whatsapp
    # Configuration-related errors
    class ConfigurationError < StandardError; end

    module Gateway
      class CloudApi
        include FlowChat::Instrumentation
        include FlowChat::GatewayAsyncSupport

        attr_reader :context

        def initialize(app, config = nil)
          @app = app
          @config = config || FlowChat::Whatsapp::Configuration.from_credentials
          @client = FlowChat::Whatsapp::Client.new(@config)

          FlowChat.logger.info { "CloudApi: Initialized WhatsApp Cloud API gateway with phone_number_id: #{@config.phone_number_id}" }
          FlowChat.logger.debug { "CloudApi: Gateway configuration - API base URL: #{FlowChat::Config.whatsapp.api_base_url}" }
        end

        def call(context)
          @context = context
          @controller = context.controller
          request = @controller.request

          FlowChat.logger.debug { "CloudApi: Processing #{request.request_method} request to #{request.path}" }

          # Skip webhook-specific handling in background mode
          unless in_background?
            # Handle webhook verification
            if request.get? && request.params["hub.mode"] == "subscribe"
              FlowChat.logger.info { "CloudApi: Handling webhook verification request" }
              return handle_verification(context)
            end
          end

          # Handle webhook messages
          if request.post?
            FlowChat.logger.info { "CloudApi: Handling webhook message (background: #{in_background?})" }
            return handle_webhook(context)
          end

          FlowChat.logger.warn { "CloudApi: Invalid request method or parameters - returning bad request" }
          @controller.head :bad_request
        end

        # Expose client for out-of-band messaging
        attr_reader :client

        private

        def determine_message_handler(context)
          # Use simulator mode if enabled, otherwise always use inline
          if context["simulator_mode"]
            FlowChat.logger.debug { "CloudApi: Using simulator message handler" }
            :simulator
          else
            FlowChat.logger.debug { "CloudApi: Using inline message handler" }
            :inline
          end
        end

        def handle_verification(context)
          params = @controller.request.params

          verify_token = @config.verify_token
          provided_token = params["hub.verify_token"]
          challenge = params["hub.challenge"]

          FlowChat.logger.debug { "CloudApi: Webhook verification - provided token matches: #{provided_token == verify_token}" }

          if provided_token == verify_token
            # Use instrumentation for webhook verification success
            instrument(Events::WEBHOOK_VERIFIED, {
              challenge: challenge,
              platform: :whatsapp
            })

            @controller.render plain: challenge
          else
            # Use instrumentation for webhook verification failure
            instrument(Events::WEBHOOK_FAILED, {
              reason: "Invalid verify token",
              platform: :whatsapp
            })

            @controller.head :forbidden
          end
        end

        def handle_webhook(context)
          # Parse body
          begin
            parse_request_body(@controller.request)
            FlowChat.logger.debug { "CloudApi: Successfully parsed webhook request body" }
          rescue JSON::ParserError => e
            FlowChat.logger.error { "CloudApi: Failed to parse webhook body: #{e.message}" }
            return @controller.head :bad_request
          end

          # Check for simulator mode parameter in request (before validation)
          # But only enable if valid simulator token is provided
          is_simulator_mode = simulate?(context)
          if is_simulator_mode
            FlowChat.logger.info { "CloudApi: Simulator mode enabled for this request" }
            context["simulator_mode"] = true
          end

          # Validate webhook signature for security (skip for simulator mode and background)
          unless in_background? || is_simulator_mode || valid_webhook_signature?(@controller.request)
            FlowChat.logger.warn { "CloudApi: Invalid webhook signature received - rejecting request" }
            return @controller.head :unauthorized
          end

          FlowChat.logger.debug { "CloudApi: Webhook signature validation passed" }

          # Extract message data from WhatsApp webhook
          entry = @body.dig("entry", 0)
          unless entry
            FlowChat.logger.debug { "CloudApi: No entry found in webhook body - returning OK" }
            return @controller.head :ok
          end

          changes = entry.dig("changes", 0)
          unless changes
            FlowChat.logger.debug { "CloudApi: No changes found in webhook entry - returning OK" }
            return @controller.head :ok
          end

          value = changes["value"]
          unless value
            FlowChat.logger.debug { "CloudApi: No value found in webhook changes - returning OK" }
            return @controller.head :ok
          end

          # Handle incoming messages
          if value["messages"]&.any?
            message = value["messages"].first
            contact = value["contacts"]&.first

            phone_number = FlowChat::PhoneNumberUtil.to_e164(message["from"])
            message_id = message["id"]
            contact_name = contact&.dig("profile", "name")
            business_phone_number = value.dig("metadata", "display_phone_number")
            business_phone_number_id = value.dig("metadata", "phone_number_id")

            # Validate that webhook is for our configured phone number
            if business_phone_number_id != @config.phone_number_id
              FlowChat.logger.warn { "CloudApi: Webhook received for phone_number_id '#{business_phone_number_id}' but configured for '#{@config.phone_number_id}' - rejecting" }
              return @controller.head :forbidden
            end

            context["request.id"] = phone_number
            context["request.user_id"] = phone_number
            context["request.user_name"] = contact_name if contact_name
            context["request.msisdn"] = phone_number
            context["request.gateway"] = :whatsapp_cloud_api
            context["request.platform"] = :whatsapp
            context["request.message_id"] = message_id
            context["request.timestamp"] = Time.current.iso8601
            context["request.body"] = @body

            context["whatsapp.business.phone_number"] = FlowChat::PhoneNumberUtil.to_e164(business_phone_number)
            context["whatsapp.business.phone_number_id"] = business_phone_number_id
            context["whatsapp.client"] = @client

            # Extract message content based on type
            extract_message_content!(message, context)

            if context.input.present?
              # Use instrumentation for message received
              instrument(Events::MESSAGE_RECEIVED, {
                from: phone_number,
                message: context.input,
                message_type: message["type"],
                message_id: message_id
              })
            end

            FlowChat.logger.debug { "CloudApi: Message content extracted - Type: #{message["type"]}, Input: '#{context.input}'" }

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

          # Handle message status updates
          if value["statuses"]&.any?
            statuses = value["statuses"]
            FlowChat.logger.info { "CloudApi: Received #{statuses.size} status update(s)" }
            FlowChat.logger.debug { "CloudApi: Status updates: #{statuses.inspect}" }
          end

          @controller.head :ok
        end

        # Validate webhook signature to ensure request comes from WhatsApp
        def valid_webhook_signature?(request)
          # Check if signature validation is explicitly disabled
          if @config.skip_signature_validation
            FlowChat.logger.debug { "CloudApi: Webhook signature validation is disabled" }
            return true
          end

          # Require app_secret for signature validation
          unless @config.app_secret && !@config.app_secret.empty?
            error_msg = "WhatsApp app_secret is required for webhook signature validation. " \
                       "Either configure app_secret or set skip_signature_validation=true to explicitly disable validation."
            FlowChat.logger.error { "CloudApi: #{error_msg}" }
            raise FlowChat::Whatsapp::ConfigurationError, error_msg
          end

          signature_header = request.headers["X-Hub-Signature-256"]
          unless signature_header
            FlowChat.logger.warn { "CloudApi: No X-Hub-Signature-256 header found in request" }
            return false
          end

          # Extract signature from header (format: "sha256=<signature>")
          expected_signature = signature_header.sub("sha256=", "")

          # Get raw request body
          request.body.rewind
          body = request.body.read
          request.body.rewind

          # Calculate HMAC signature
          calculated_signature = OpenSSL::HMAC.hexdigest(
            OpenSSL::Digest.new("sha256"),
            @config.app_secret,
            body
          )

          # Compare signatures using secure comparison to prevent timing attacks
          signature_valid = secure_compare(expected_signature, calculated_signature)

          if signature_valid
            FlowChat.logger.debug { "CloudApi: Webhook signature validation successful" }
          else
            FlowChat.logger.warn { "CloudApi: Webhook signature validation failed - signatures do not match" }
          end

          signature_valid
        rescue FlowChat::Whatsapp::ConfigurationError
          raise
        rescue => e
          FlowChat.logger.error { "CloudApi: Error validating webhook signature: #{e.class.name}: #{e.message}" }
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

        def extract_message_content!(message, context)
          message_type = message["type"]
          FlowChat.logger.debug { "CloudApi: Extracting content from #{message_type} message" }

          case message_type
          when "text"
            content = message.dig("text", "body")
            context.input = content.presence || ""
            FlowChat.logger.debug { "CloudApi: Text message content: '#{content}'" }
          when "interactive"
            # Handle button/list replies
            if message.dig("interactive", "type") == "button_reply"
              content = message.dig("interactive", "button_reply", "id")
              context.input = content
              FlowChat.logger.debug { "CloudApi: Button reply ID: '#{content}'" }
            elsif message.dig("interactive", "type") == "list_reply"
              content = message.dig("interactive", "list_reply", "id")
              context.input = content
              FlowChat.logger.debug { "CloudApi: List reply ID: '#{content}'" }
            end
          when "location"
            location = {
              latitude: message.dig("location", "latitude"),
              longitude: message.dig("location", "longitude"),
              name: message.dig("location", "name"),
              address: message.dig("location", "address")
            }
            context["request.location"] = location
            context.input = FlowChat::Input::LOCATION
            FlowChat.logger.debug { "CloudApi: Location received - Lat: #{location[:latitude]}, Lng: #{location[:longitude]}" }
          when "image", "document", "audio", "video", "sticker"
            media_data = message[message["type"]]
            context["request.media"] = {
              type: message["type"].to_sym,
              id: media_data["id"],
              mime_type: media_data["mime_type"],
              caption: media_data["caption"],
              filename: media_data["filename"],
              sha256: media_data["sha256"],
              animated: media_data["animated"]
            }
            context.input = FlowChat::Input::MEDIA
            FlowChat.logger.debug { "CloudApi: Media received - Type: #{message["type"]}, ID: #{media_data["id"]}" }
          when "contacts"
            # WhatsApp sends contacts as an array, take the first one
            contact_data = message.dig("contacts", 0)
            if contact_data
              phones = contact_data.dig("phones") || []
              context["request.contact"] = {
                name: contact_data.dig("name", "formatted_name"),
                first_name: contact_data.dig("name", "first_name"),
                last_name: contact_data.dig("name", "last_name"),
                phones: phones.map { |p| p["phone"] },
                phone_number: phones.first&.dig("phone")
              }
              context.input = FlowChat::Input::CONTACT
              FlowChat.logger.debug { "CloudApi: Contact received - Name: #{context["request.contact"][:name]}" }
            end
          end
        end

        def handle_message_inline(context, controller)
          response = @app.call(context)
          if response
            type, prompt, choices, media = response
            result = @client.send_message(context["request.msisdn"], prompt, choices: choices, media: media)
            context["whatsapp.message_result"] = result

            # Instrument message sent
            instrument(Events::MESSAGE_SENT, {
              to: context["request.msisdn"],
              session_id: context["request.id"],
              message: prompt,
              message_type: (type == :prompt) ? "prompt" : "terminal",
              gateway: :whatsapp_cloud_api,
              platform: :whatsapp,
              content_length: prompt.to_s.length,
              timestamp: context["request.timestamp"]
            })
          end
        end

        def handle_message_simulator(context, controller)
          response = @app.call(context)

          if response
            _, prompt, choices, media = response
            response_data = render_response(prompt, choices, media)

            # For simulator mode, return the response data in the HTTP response
            # instead of actually sending via WhatsApp API
            message_payload = @client.build_message_payload(response_data, context["request.msisdn"])

            simulator_response = {
              mode: "simulator",
              webhook_processed: true,
              would_send: message_payload,
              message_info: {
                to: context["request.msisdn"],
                contact_name: context["request.user_name"],
                timestamp: Time.now.iso8601
              }
            }

            controller.render json: simulator_response
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
          return @body if @body

          if request.body.nil?
            FlowChat.logger.debug { "CloudApi: Request body is nil, returning empty hash" }
            @body = {}
          else
            request.body.rewind if request.body.respond_to?(:rewind)
            @body = JSON.parse(request.body.read)
          end
        end

        def render_response(prompt, choices, media)
          FlowChat::Whatsapp::Renderer.new(prompt, choices: choices, media: media).render
        end

        # Configure WhatsApp-specific middleware stack
        def self.configure_middleware_stack(builder, custom_middleware)
          FlowChat.logger.debug { "CloudApi: Configuring WhatsApp middleware stack" }

          builder.use custom_middleware
          FlowChat.logger.debug { "CloudApi: Added custom middleware" }

          builder.use FlowChat::Whatsapp::Middleware::ChoiceMapper
          FlowChat.logger.debug { "CloudApi: Added Whatsapp::Middleware::ChoiceMapper" }
        end
      end
    end
  end
end

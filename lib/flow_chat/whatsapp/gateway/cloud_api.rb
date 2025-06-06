require "net/http"
require "json"
require "phonelib"
require "openssl"

module FlowChat
  module Whatsapp
    # Configuration-related errors
    class ConfigurationError < StandardError; end

    module Gateway
      class CloudApi
        def initialize(app, config = nil)
          @app = app
          @config = config || FlowChat::Whatsapp::Configuration.from_credentials
          @client = FlowChat::Whatsapp::Client.new(@config)
          
          FlowChat.logger.info { "CloudApi: Initialized WhatsApp Cloud API gateway with phone_number_id: #{@config.phone_number_id}" }
          FlowChat.logger.debug { "CloudApi: Gateway configuration - API base URL: #{FlowChat::Config.whatsapp.api_base_url}" }
        end

        def call(context)
          controller = context.controller
          request = controller.request

          FlowChat.logger.debug { "CloudApi: Processing #{request.request_method} request to #{request.path}" }

          # Handle webhook verification
          if request.get? && request.params["hub.mode"] == "subscribe"
            FlowChat.logger.info { "CloudApi: Handling webhook verification request" }
            return handle_verification(context)
          end

          # Handle webhook messages
          if request.post?
            FlowChat.logger.info { "CloudApi: Handling webhook message" }
            return handle_webhook(context)
          end

          FlowChat.logger.warn { "CloudApi: Invalid request method or parameters - returning bad request" }
          controller.head :bad_request
        end

        # Expose client for out-of-band messaging
        attr_reader :client

        private

        def determine_message_handler(context)
          # Check if simulator mode was already detected and set in context
          if context["simulator_mode"]
            FlowChat.logger.debug { "CloudApi: Using simulator message handler" }
            return :simulator
          end

          # Use global WhatsApp configuration
          mode = FlowChat::Config.whatsapp.message_handling_mode
          FlowChat.logger.debug { "CloudApi: Using #{mode} message handling mode" }
          mode
        end

        def handle_verification(context)
          controller = context.controller
          params = controller.request.params

          verify_token = @config.verify_token
          provided_token = params["hub.verify_token"]
          challenge = params["hub.challenge"]

          FlowChat.logger.debug { "CloudApi: Webhook verification - provided token matches: #{provided_token == verify_token}" }

          if provided_token == verify_token
            FlowChat.logger.info { "CloudApi: Webhook verification successful - returning challenge: #{challenge}" }
            controller.render plain: challenge
          else
            FlowChat.logger.warn { "CloudApi: Webhook verification failed - invalid verify token" }
            controller.head :forbidden
          end
        end

        def handle_webhook(context)
          controller = context.controller
          
          # Parse body
          begin
            parse_request_body(controller.request)
            FlowChat.logger.debug { "CloudApi: Successfully parsed webhook request body" }
          rescue JSON::ParserError => e
            FlowChat.logger.error { "CloudApi: Failed to parse webhook body: #{e.message}" }
            return controller.head :bad_request
          end
          
          # Check for simulator mode parameter in request (before validation)
          # But only enable if valid simulator token is provided
          is_simulator_mode = simulate?(context)
          if is_simulator_mode
            FlowChat.logger.info { "CloudApi: Simulator mode enabled for this request" }
            context["simulator_mode"] = true
          end

          # Validate webhook signature for security (skip for simulator mode)
          unless is_simulator_mode || valid_webhook_signature?(controller.request)
            FlowChat.logger.warn { "CloudApi: Invalid webhook signature received - rejecting request" }
            return controller.head :unauthorized
          end

          FlowChat.logger.debug { "CloudApi: Webhook signature validation passed" }

          # Extract message data from WhatsApp webhook
          entry = @body.dig("entry", 0)
          unless entry
            FlowChat.logger.debug { "CloudApi: No entry found in webhook body - returning OK" }
            return controller.head :ok
          end

          changes = entry.dig("changes", 0)
          unless changes
            FlowChat.logger.debug { "CloudApi: No changes found in webhook entry - returning OK" }
            return controller.head :ok
          end

          value = changes["value"]
          unless value
            FlowChat.logger.debug { "CloudApi: No value found in webhook changes - returning OK" }
            return controller.head :ok
          end

          # Handle incoming messages
          if value["messages"]&.any?
            message = value["messages"].first
            contact = value["contacts"]&.first

            phone_number = message["from"]
            message_id = message["id"]
            contact_name = contact&.dig("profile", "name")

            FlowChat.logger.info { "CloudApi: Processing message from #{phone_number} (#{contact_name || 'Unknown'}), message_id: #{message_id}" }

            context["request.id"] = phone_number
            context["request.gateway"] = :whatsapp_cloud_api
            context["request.message_id"] = message_id
            context["request.msisdn"] = Phonelib.parse(phone_number).e164
            context["request.contact_name"] = contact_name
            context["request.timestamp"] = message["timestamp"]

            # Extract message content based on type
            extract_message_content(message, context)

            FlowChat.logger.debug { "CloudApi: Message content extracted - Type: #{message["type"]}, Input: '#{context.input}'" }

            # Determine message handling mode
            handler_mode = determine_message_handler(context)

            # Process the message based on handling mode
            case handler_mode
            when :inline
              handle_message_inline(context, controller)
            when :background
              handle_message_background(context, controller)
            when :simulator
              # Return early from simulator mode to preserve the JSON response
              return handle_message_simulator(context, controller)
            end
          end

          # Handle message status updates
          if value["statuses"]&.any?
            statuses = value["statuses"]
            FlowChat.logger.info { "CloudApi: Received #{statuses.size} status update(s)" }
            FlowChat.logger.debug { "CloudApi: Status updates: #{statuses.inspect}" }
          end

          controller.head :ok
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

        def extract_message_content(message, context)
          message_type = message["type"]
          FlowChat.logger.debug { "CloudApi: Extracting content from #{message_type} message" }
          
          case message_type
          when "text"
            content = message.dig("text", "body")
            context.input = content
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
            context.input = "$location$"
            FlowChat.logger.debug { "CloudApi: Location received - Lat: #{location[:latitude]}, Lng: #{location[:longitude]}" }
          when "image", "document", "audio", "video"
            context["request.media"] = {
              type: message["type"],
              id: message.dig(message["type"], "id"),
              mime_type: message.dig(message["type"], "mime_type"),
              caption: message.dig(message["type"], "caption")
            }
            context.input = "$media$"
          end
        end

        def handle_message_inline(context, controller)
          response = @app.call(context)
          if response
            _type, prompt, choices, media = response
            rendered_message = render_response(prompt, choices, media)
            result = @client.send_message(context["request.msisdn"], rendered_message)
            context["whatsapp.message_result"] = result
          end
        end

        def handle_message_background(context, controller)
          # Process the flow synchronously (maintaining controller context)
          response = @app.call(context)

          if response
            _type, prompt, choices, media = response
            rendered_message = render_response(prompt, choices, media)
            
            # Queue only the response delivery asynchronously
            send_data = {
              msisdn: context["request.msisdn"],
              response: rendered_message,
              config_name: @config.name
            }

            # Get job class from configuration
            job_class_name = FlowChat::Config.whatsapp.background_job_class

            # Enqueue background job for sending only
            begin
              job_class = job_class_name.constantize
              job_class.perform_later(send_data)
            rescue NameError
              # Fallback to inline sending if no job system
              Rails.logger.warn "Background mode requested but no #{job_class_name} found. Falling back to inline sending."
              result = @client.send_message(context["request.msisdn"], rendered_message)
              context["whatsapp.message_result"] = result
            end
          end
        end

        def handle_message_simulator(context, controller)
          response = @app.call(context)

          if response
            _type, prompt, choices, media = response
            rendered_message = render_response(prompt, choices, media)
            
            # For simulator mode, return the response data in the HTTP response
            # instead of actually sending via WhatsApp API
            message_payload = @client.build_message_payload(rendered_message, context["request.msisdn"])

            simulator_response = {
              mode: "simulator",
              webhook_processed: true,
              would_send: message_payload,
              message_info: {
                to: context["request.msisdn"],
                contact_name: context["request.contact_name"],
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
          request = context.controller.request
          simulator_cookie = request.cookies["flowchat_simulator"]
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
          FlowChat::Whatsapp::Renderer.new(prompt, choices: choices, media: media).render
        end
      end
    end
  end
end

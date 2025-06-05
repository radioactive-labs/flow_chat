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
        end

        def call(context)
          controller = context.controller
          request = controller.request

          # Handle webhook verification
          if request.get? && request.params["hub.mode"] == "subscribe"
            return handle_verification(context)
          end

          # Handle webhook messages
          if request.post?
            return handle_webhook(context)
          end

          controller.head :bad_request
        end

        # Expose client for out-of-band messaging
        attr_reader :client

        private

        def determine_message_handler(context)
          # Check if simulator mode was already detected and set in context
          if context["simulator_mode"]
            return :simulator
          end

          # Use global WhatsApp configuration
          FlowChat::Config.whatsapp.message_handling_mode
        end

        def handle_verification(context)
          controller = context.controller
          params = controller.request.params

          verify_token = @config.verify_token

          if params["hub.verify_token"] == verify_token
            controller.render plain: params["hub.challenge"]
          else
            controller.head :forbidden
          end
        end

        def handle_webhook(context)
          controller = context.controller
          
          # Parse body
          begin
            parse_request_body(controller.request)
          rescue JSON::ParserError => e
            Rails.logger.warn "Failed to parse webhook body: #{e.message}"
            return controller.head :bad_request
          end
          
          # Check for simulator mode parameter in request (before validation)
          # But only enable if valid simulator token is provided
          is_simulator_mode = simulate?(context)
          if is_simulator_mode
            context["simulator_mode"] = true
          end

          # Validate webhook signature for security (skip for simulator mode)
          unless is_simulator_mode || valid_webhook_signature?(controller.request)
            Rails.logger.warn "Invalid webhook signature received"
            return controller.head :unauthorized
          end

          # Extract message data from WhatsApp webhook
          entry = @body.dig("entry", 0)
          return controller.head :ok unless entry

          changes = entry.dig("changes", 0)
          return controller.head :ok unless changes

          value = changes["value"]
          return controller.head :ok unless value

          # Handle incoming messages
          if value["messages"]&.any?
            message = value["messages"].first
            contact = value["contacts"]&.first

            context["request.id"] = message["from"]
            context["request.gateway"] = :whatsapp_cloud_api
            context["request.message_id"] = message["id"]
            context["request.msisdn"] = Phonelib.parse(message["from"]).e164
            context["request.contact_name"] = contact&.dig("profile", "name")
            context["request.timestamp"] = message["timestamp"]

            # Extract message content based on type
            extract_message_content(message, context)

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
            Rails.logger.info "WhatsApp status update: #{value["statuses"]}"
          end

          controller.head :ok
        end

        # Validate webhook signature to ensure request comes from WhatsApp
        def valid_webhook_signature?(request)
          # Check if signature validation is explicitly disabled
          if @config.skip_signature_validation
            return true
          end

          # Require app_secret for signature validation
          unless @config.app_secret && !@config.app_secret.empty?
            raise FlowChat::Whatsapp::ConfigurationError, 
              "WhatsApp app_secret is required for webhook signature validation. " \
              "Either configure app_secret or set skip_signature_validation=true to explicitly disable validation."
          end

          signature_header = request.headers["X-Hub-Signature-256"]
          return false unless signature_header

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
          secure_compare(expected_signature, calculated_signature)
        rescue FlowChat::Whatsapp::ConfigurationError
          raise
        rescue => e
          Rails.logger.error "Error validating webhook signature: #{e.message}"
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
          case message["type"]
          when "text"
            context.input = message.dig("text", "body")
          when "interactive"
            # Handle button/list replies
            if message.dig("interactive", "type") == "button_reply"
              context.input = message.dig("interactive", "button_reply", "id")
            elsif message.dig("interactive", "type") == "list_reply"
              context.input = message.dig("interactive", "list_reply", "id")
            end
          when "location"
            context["request.location"] = {
              latitude: message.dig("location", "latitude"),
              longitude: message.dig("location", "longitude"),
              name: message.dig("location", "name"),
              address: message.dig("location", "address")
            }
            context.input = "$location$"
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
            result = @client.send_message(context["request.msisdn"], response)
            context["whatsapp.message_result"] = result
          end
        end

        def handle_message_background(context, controller)
          # Process the flow synchronously (maintaining controller context)
          response = @app.call(context)

          if response
            # Queue only the response delivery asynchronously
            send_data = {
              msisdn: context["request.msisdn"],
              response: response,
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
              result = @client.send_message(context["request.msisdn"], response)
              context["whatsapp.message_result"] = result
            end
          end
        end

        def handle_message_simulator(context, controller)
          response = @app.call(context)

          if response
            # For simulator mode, return the response data in the HTTP response
            # instead of actually sending via WhatsApp API
            message_payload = @client.build_message_payload(response, context["request.msisdn"])

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
      end
    end
  end
end

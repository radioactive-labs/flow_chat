require "net/http"
require "json"
require "openssl"
require "base64"
require "twilio-ruby"

module FlowChat
  module Whatsapp
    module Gateway
      class Twilio
        include FlowChat::Instrumentation

        attr_reader :context

        def initialize(app, config = nil)
          @app = app
          @config = config || FlowChat::Whatsapp::TwilioConfiguration.from_credentials
          @client = FlowChat::Whatsapp::TwilioClient.new(@config)

          FlowChat.logger.info { "Twilio: Initialized Twilio WhatsApp gateway with account_sid: #{@config.account_sid}" }
          FlowChat.logger.debug { "Twilio: Gateway configuration - API base URL: #{@config.api_base_url}" }
        end

        def call(context)
          @context = context
          controller = context.controller
          request = controller.request

          FlowChat.logger.debug { "Twilio: Processing #{request.request_method} request to #{request.path}" }

          # Handle webhook messages (Twilio sends POST requests)
          if request.post?
            FlowChat.logger.info { "Twilio: Handling webhook message" }
            return handle_webhook(context)
          end

          FlowChat.logger.warn { "Twilio: Invalid request method - returning bad request" }
          controller.head :bad_request
        end

        # Expose client for out-of-band messaging
        attr_reader :client

        private

        def determine_message_handler(context)
          # Use simulator mode if enabled, otherwise always use inline
          if context["simulator_mode"]
            FlowChat.logger.debug { "Twilio: Using simulator message handler" }
            :simulator
          else
            FlowChat.logger.debug { "Twilio: Using inline message handler" }
            :inline
          end
        end

        def handle_webhook(context)
          controller = context.controller
          request = controller.request

          # Parse form-encoded body (Twilio sends application/x-www-form-urlencoded)
          begin
            parse_request_body(request)
            FlowChat.logger.debug { "Twilio: Successfully parsed webhook request body" }
          rescue => e
            FlowChat.logger.error { "Twilio: Failed to parse webhook body: #{e.message}" }
            return controller.head :bad_request
          end

          # Check for simulator mode parameter in request (before validation)
          is_simulator_mode = simulate?(context)
          if is_simulator_mode
            FlowChat.logger.info { "Twilio: Simulator mode enabled for this request" }
            context["simulator_mode"] = true
          end

          # Extract message data from Twilio webhook first
          message_sid = @params["MessageSid"]
          unless message_sid
            FlowChat.logger.debug { "Twilio: No MessageSid found in webhook - returning bad request" }
            return controller.head :bad_request
          end

          # Validate webhook signature for security (skip for simulator mode)
          unless is_simulator_mode || valid_webhook_signature?(request)
            FlowChat.logger.warn { "Twilio: Invalid webhook signature received - rejecting request" }
            return controller.head :unauthorized
          end

          FlowChat.logger.debug { "Twilio: Webhook signature validation passed" }

          # Extract phone numbers and convert from WhatsApp format (whatsapp:+1234567890)
          from_raw = @params["From"]
          to_raw = @params["To"]

          unless from_raw&.start_with?("whatsapp:")
            FlowChat.logger.debug { "Twilio: Not a WhatsApp message - returning OK" }
            return controller.head :ok
          end

          phone_number = FlowChat::PhoneNumberUtil.to_e164(from_raw.sub("whatsapp:", ""))
          to_number = to_raw.sub("whatsapp:", "") if to_raw

          context["request.id"] = phone_number
          context["request.msisdn"] = phone_number
          context["request.user_id"] = context["request.msisdn"]
          context["request.gateway"] = :whatsapp_twilio
          context["request.platform"] = :whatsapp
          context["request.message_id"] = message_sid
          context["request.timestamp"] = Time.current.iso8601
          context["request.to_number"] = to_number

          context["twilio.client"] = @client
          context["twilio.params"] = @params

          # Extract message content
          extract_message_content!(@params, context)

          if context.input.present?
            # Use instrumentation for message received
            instrument(Events::MESSAGE_RECEIVED, {
              from: phone_number,
              message: context.input,
              message_id: message_sid,
              platform: :whatsapp
            })
          end

          FlowChat.logger.debug { "Twilio: Message content extracted - Input: '#{context.input}'" }

          # Determine message handling mode
          handler_mode = determine_message_handler(context)

          # Process the message based on handling mode
          case handler_mode
          when :inline
            handle_message_inline(context, controller)
          when :simulator
            # Return early from simulator mode to preserve the JSON response
            handle_message_simulator(context, controller)
          end
        end

        # Validate webhook signature to ensure request comes from Twilio
        def valid_webhook_signature?(request)
          # Check if signature validation is explicitly disabled
          if @config.skip_signature_validation
            FlowChat.logger.debug { "Twilio: Webhook signature validation is disabled" }
            return true
          end

          # Require auth_token for signature validation
          unless @config.auth_token && !@config.auth_token.empty?
            error_msg = "Twilio auth_token is required for webhook signature validation. " \
                       "Either configure auth_token or set skip_signature_validation=true to explicitly disable validation."
            FlowChat.logger.error { "Twilio: #{error_msg}" }
            raise FlowChat::Whatsapp::ConfigurationError, error_msg
          end

          signature_header = request.headers["X-Twilio-Signature"]
          unless signature_header
            FlowChat.logger.warn { "Twilio: No X-Twilio-Signature header found in request" }
            return false
          end

          # Build the signature string: URL + sorted POST params
          url = request.url
          post_params = request.POST || {}

          signature_string = url + post_params.sort.map { |k, v| "#{k}#{v}" }.join

          # Calculate HMAC signature
          calculated_signature = Base64.strict_encode64(
            OpenSSL::HMAC.digest(
              OpenSSL::Digest.new("sha1"),
              @config.auth_token,
              signature_string
            )
          )

          # Compare signatures using secure comparison to prevent timing attacks
          signature_valid = secure_compare(signature_header, calculated_signature)

          if signature_valid
            FlowChat.logger.debug { "Twilio: Webhook signature validation successful" }
          else
            FlowChat.logger.warn { "Twilio: Webhook signature validation failed - signatures do not match" }
          end

          signature_valid
        rescue FlowChat::Whatsapp::ConfigurationError
          raise
        rescue => e
          FlowChat.logger.error { "Twilio: Error validating webhook signature: #{e.class.name}: #{e.message}" }
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

        def extract_message_content!(params, context)
          FlowChat.logger.debug { "Twilio: Extracting content from webhook params" }

          # Handle text content
          FlowChat.logger.debug { "Twilio: Text message content: '#{params["Body"]}'" }
          context.input = params["Body"].presence || ""

          # Handle media content
          num_media = params["NumMedia"].to_i
          if num_media > 0
            media_items = []
            (0...num_media).each do |i|
              media_url = params["MediaUrl#{i}"]
              content_type = params["MediaContentType#{i}"]

              if media_url && content_type
                media_item = {
                  url: media_url,
                  content_type: content_type
                }
                media_items << media_item
              end
            end

            if media_items.any?
              context["request.media"] = {
                type: determine_media_type(media_items.first[:content_type]),
                items: media_items
              }
              context.input = "$media$"
              FlowChat.logger.debug { "Twilio: Media message received - #{media_items.size} items" }
            end
          end

          # Handle location (if supported by future Twilio features)
          if params["Latitude"] && params["Longitude"]
            location = {
              latitude: params["Latitude"].to_f,
              longitude: params["Longitude"].to_f,
              address: params["Address"]
            }
            context["request.location"] = location
            context.input = "$location$"
            FlowChat.logger.debug { "Twilio: Location received - Lat: #{location[:latitude]}, Lng: #{location[:longitude]}" }
          end
        end

        def determine_media_type(content_type)
          return "unknown" unless content_type

          case content_type
          when /^image\//
            "image"
          when /^audio\//
            "audio"
          when /^video\//
            "video"
          when /^application\/pdf/
            "document"
          else
            "document"
          end
        end

        def handle_message_inline(context, controller)
          response = @app.call(context)
          if response
            type, prompt, choices, media = response

            # Use TwiML renderer to generate TwiML directly
            twiml_response = render_twiml_response(prompt, choices, media)
            context["twilio.twiml_response"] = twiml_response

            # Instrument message sent
            instrument(Events::MESSAGE_SENT, {
              to: context["request.msisdn"],
              session_id: context["request.id"],
              message: prompt,
              message_type: (type == :prompt) ? "prompt" : "terminal",
              gateway: :whatsapp_twilio,
              platform: :whatsapp,
              content_length: prompt.to_s.length,
              timestamp: context["request.timestamp"]
            })

            # Return TwiML response
            controller.render xml: twiml_response
          else
            # Return empty TwiML response
            controller.render xml: generate_empty_twiml
          end
        end

        def handle_message_simulator(context, controller)
          response = @app.call(context)

          if response
            _, prompt, choices, media = response
            response_data = render_response(prompt, choices, media)

            # For simulator mode, return the response data in the HTTP response
            # instead of actually sending via Twilio API
            message_payload = @client.build_message_payload(response_data, context["request.msisdn"])

            simulator_response = {
              mode: "simulator",
              webhook_processed: true,
              would_send: message_payload,
              message_info: {
                to: context["request.msisdn"],
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
          @params["simulator_mode"] && valid_simulator_cookie?(context)
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
          @params ||= request.POST || {}
        end

        def render_response(prompt, choices, media)
          FlowChat::Whatsapp::Renderer.new(prompt, choices: choices, media: media).render
        end

        def render_twiml_response(prompt, choices, media)
          FlowChat::Whatsapp::TwimlRenderer.new(prompt, choices: choices, media: media).render
        end

        def generate_empty_twiml
          ::Twilio::TwiML::MessagingResponse.new.to_s
        end
      end
    end
  end
end

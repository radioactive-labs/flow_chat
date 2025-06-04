require "net/http"
require "json"
require "phonelib"

module FlowChat
  module Whatsapp
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
          # Check for simulator parameter in request (highest priority)
          if context["simulator_mode"] || context.controller.request.params["simulator_mode"]
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
          body = JSON.parse(controller.request.body.read)

          # Check for simulator mode parameter in request
          if body.dig("simulator_mode") || controller.request.params["simulator_mode"]
            context["simulator_mode"] = true
          end

          # Extract message data from WhatsApp webhook
          entry = body.dig("entry", 0)
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
      end
    end
  end
end

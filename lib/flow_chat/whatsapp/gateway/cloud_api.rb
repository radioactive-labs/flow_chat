require "net/http"
require "json"
require "phonelib"

module FlowChat
  module Whatsapp
    module Gateway
      class CloudApi
        WHATSAPP_API_URL = "https://graph.facebook.com/v18.0"

        def initialize(app)
          @app = app
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

        private

        def handle_verification(context)
          controller = context.controller
          params = controller.request.params

          verify_token = Rails.application.credentials.dig(:whatsapp, :verify_token)
          
          if params["hub.verify_token"] == verify_token
            controller.render plain: params["hub.challenge"]
          else
            controller.head :forbidden
          end
        end

        def handle_webhook(context)
          controller = context.controller
          body = JSON.parse(controller.request.body.read)

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
              # Set input so screen can proceed
              context.input = "$location$"
            when "image", "document", "audio", "video"
              context["request.media"] = {
                type: message["type"],
                id: message.dig(message["type"], "id"),
                mime_type: message.dig(message["type"], "mime_type"),
                caption: message.dig(message["type"], "caption")
              }
              # Set input so screen can proceed
              context.input = "$media$"
            end

            response = @app.call(context)
            send_whatsapp_message(context, response)
          end

          # Handle message status updates
          if value["statuses"]&.any?
            # Log status updates but don't process them
            Rails.logger.info "WhatsApp status update: #{value["statuses"]}"
          end

          controller.head :ok
        end

        def send_whatsapp_message(context, response)
          return unless response

          phone_number_id = Rails.application.credentials.dig(:whatsapp, :phone_number_id)
          access_token = Rails.application.credentials.dig(:whatsapp, :access_token)
          to = context["request.msisdn"]

          message_data = build_message_payload(response, to)

          uri = URI("#{WHATSAPP_API_URL}/#{phone_number_id}/messages")
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true

          request = Net::HTTP::Post.new(uri)
          request["Authorization"] = "Bearer #{access_token}"
          request["Content-Type"] = "application/json"
          request.body = message_data.to_json

          response = http.request(request)
          
          unless response.is_a?(Net::HTTPSuccess)
            Rails.logger.error "WhatsApp API error: #{response.body}"
          end
        end

        def build_message_payload(response, to)
          type, content, options = response

          case type
          when :text
            {
              messaging_product: "whatsapp",
              to: to,
              type: "text",
              text: { body: content }
            }
          when :interactive_buttons
            {
              messaging_product: "whatsapp",
              to: to,
              type: "interactive",
              interactive: {
                type: "button",
                body: { text: content },
                action: {
                  buttons: options[:buttons].map.with_index do |button, index|
                    {
                      type: "reply",
                      reply: {
                        id: button[:id] || index.to_s,
                        title: button[:title]
                      }
                    }
                  end
                }
              }
            }
          when :interactive_list
            {
              messaging_product: "whatsapp",
              to: to,
              type: "interactive",
              interactive: {
                type: "list",
                body: { text: content },
                action: {
                  button: options[:button_text] || "Choose",
                  sections: options[:sections]
                }
              }
            }
          when :template
            {
              messaging_product: "whatsapp",
              to: to,
              type: "template",
              template: {
                name: options[:template_name],
                language: { code: options[:language] || "en_US" },
                components: options[:components] || []
              }
            }
          else
            # Default to text message
            {
              messaging_product: "whatsapp",
              to: to,
              type: "text",
              text: { body: content.to_s }
            }
          end
        end
      end
    end
  end
end 
require "net/http"
require "json"

module FlowChat
  module Whatsapp
    class TemplateManager
      def initialize(config = nil)
        @config = config || Configuration.from_credentials
      end

      # Send a template message (used to initiate conversations)
      def send_template(to:, template_name:, language: "en_US", components: [])
        message_data = {
          messaging_product: "whatsapp",
          to: to,
          type: "template",
          template: {
            name: template_name,
            language: {code: language},
            components: components
          }
        }

        send_message(message_data)
      end

      # Common template structures
      def send_welcome_template(to:, name: nil)
        components = []

        if name
          components << {
            type: "header",
            parameters: [
              {
                type: "text",
                text: name
              }
            ]
          }
        end

        send_template(
          to: to,
          template_name: "hello_world", # Default Meta template
          language: "en_US",
          components: components
        )
      end

      def send_notification_template(to:, message:, button_text: nil)
        components = [
          {
            type: "body",
            parameters: [
              {
                type: "text",
                text: message
              }
            ]
          }
        ]

        if button_text
          components << {
            type: "button",
            sub_type: "quick_reply",
            index: "0",
            parameters: [
              {
                type: "payload",
                payload: "continue"
              }
            ]
          }
        end

        send_template(
          to: to,
          template_name: "notification_template", # Custom template
          language: "en_US",
          components: components
        )
      end

      # Create a new template (requires approval from Meta)
      def create_template(name:, category:, language: "en_US", components: [])
        business_account_id = @config.business_account_id
        uri = URI("#{FlowChat::Config.whatsapp.api_base_url}/#{business_account_id}/message_templates")

        template_data = {
          name: name,
          category: category, # AUTHENTICATION, MARKETING, UTILITY
          language: language,
          components: components
        }

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{@config.access_token}"
        request["Content-Type"] = "application/json"
        request.body = template_data.to_json

        response = http.request(request)
        JSON.parse(response.body)
      end

      # List all templates
      def list_templates
        business_account_id = @config.business_account_id
        uri = URI("#{FlowChat::Config.whatsapp.api_base_url}/#{business_account_id}/message_templates")

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "Bearer #{@config.access_token}"

        response = http.request(request)
        JSON.parse(response.body)
      end

      # Get template status
      def template_status(template_id)
        uri = URI("#{FlowChat::Config.whatsapp.api_base_url}/#{template_id}")

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "Bearer #{@config.access_token}"

        response = http.request(request)
        JSON.parse(response.body)
      end

      private

      def send_message(message_data)
        uri = URI(@config.messages_url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{@config.access_token}"
        request["Content-Type"] = "application/json"
        request.body = message_data.to_json

        response = http.request(request)

        unless response.is_a?(Net::HTTPSuccess)
          Rails.logger.error "WhatsApp Template API error: #{response.body}"
          return nil
        end

        JSON.parse(response.body)
      end
    end
  end
end

require "net/http"
require "json"

module FlowChat
  module Whatsapp
    class Client
      WHATSAPP_API_URL = "https://graph.facebook.com/v18.0"

      def initialize(config)
        @config = config
      end

      # Send a message to a WhatsApp number
      # @param to [String] Phone number in E.164 format
      # @param response [Array] FlowChat response array [type, content, options]
      # @return [Hash] API response or nil on error
      def send_message(to, response)
        message_data = build_message_payload(response, to)
        send_message_payload(message_data)
      end

      # Send a text message
      # @param to [String] Phone number in E.164 format  
      # @param text [String] Message text
      # @return [Hash] API response or nil on error
      def send_text(to, text)
        send_message(to, [:text, text, {}])
      end

      # Send interactive buttons
      # @param to [String] Phone number in E.164 format
      # @param text [String] Message text
      # @param buttons [Array] Array of button hashes with :id and :title
      # @return [Hash] API response or nil on error
      def send_buttons(to, text, buttons)
        send_message(to, [:interactive_buttons, text, { buttons: buttons }])
      end

      # Send interactive list
      # @param to [String] Phone number in E.164 format
      # @param text [String] Message text
      # @param sections [Array] List sections
      # @param button_text [String] Button text (default: "Choose")
      # @return [Hash] API response or nil on error
      def send_list(to, text, sections, button_text = "Choose")
        send_message(to, [:interactive_list, text, { sections: sections, button_text: button_text }])
      end

      # Send a template message
      # @param to [String] Phone number in E.164 format
      # @param template_name [String] Template name
      # @param components [Array] Template components
      # @param language [String] Language code (default: "en_US")
      # @return [Hash] API response or nil on error
      def send_template(to, template_name, components = [], language = "en_US")
        send_message(to, [:template, "", { 
          template_name: template_name, 
          components: components, 
          language: language 
        }])
      end

      # Build message payload for WhatsApp API
      # This method is exposed so the gateway can use it for simulator mode
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

      # Get media URL from media ID
      # @param media_id [String] Media ID from WhatsApp
      # @return [String] Media URL or nil on error
      def get_media_url(media_id)
        uri = URI("#{WHATSAPP_API_URL}/#{media_id}")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "Bearer #{@config.access_token}"

        response = http.request(request)
        
        if response.is_a?(Net::HTTPSuccess)
          data = JSON.parse(response.body)
          data["url"]
        else
          Rails.logger.error "WhatsApp Media API error: #{response.body}"
          nil
        end
      end

      # Download media content
      # @param media_id [String] Media ID from WhatsApp
      # @return [String] Media content or nil on error
      def download_media(media_id)
        media_url = get_media_url(media_id)
        return nil unless media_url

        uri = URI(media_url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "Bearer #{@config.access_token}"

        response = http.request(request)
        
        if response.is_a?(Net::HTTPSuccess)
          response.body
        else
          Rails.logger.error "WhatsApp Media download error: #{response.body}"
          nil
        end
      end

      private

      # Send message payload to WhatsApp API
      # @param message_data [Hash] Message payload
      # @return [Hash] API response or nil on error
      def send_message_payload(message_data)
        uri = URI("#{WHATSAPP_API_URL}/#{@config.phone_number_id}/messages")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{@config.access_token}"
        request["Content-Type"] = "application/json"
        request.body = message_data.to_json

        response = http.request(request)
        
        if response.is_a?(Net::HTTPSuccess)
          JSON.parse(response.body)
        else
          Rails.logger.error "WhatsApp API error: #{response.body}"
          nil
        end
      end
    end
  end
end 
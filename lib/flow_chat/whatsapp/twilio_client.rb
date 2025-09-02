require "net/http"
require "json"
require "uri"
require "base64"

module FlowChat
  module Whatsapp
    class TwilioClient
      include FlowChat::Instrumentation

      def initialize(config)
        @config = config
        FlowChat.logger.info { "Twilio::Client: Initialized Twilio WhatsApp client for phone_number: #{@config.phone_number}" }
        FlowChat.logger.debug { "Twilio::Client: API base URL: #{@config.api_base_url}" }
      end

      # Send a message to a WhatsApp number
      # @param to [String] Phone number in E.164 format
      # @param response [Array] FlowChat response array [type, content, options]
      # @return [Hash] API response or nil on error
      def send_message(to, prompt, choices: nil, media: nil)
        FlowChat.logger.info { "Twilio::Client: Sending message to #{to}" }
        FlowChat.logger.debug { "Twilio::Client: Message content: '#{prompt.to_s.truncate(100)}'" }

        # Use renderer to convert to structured response
        response = FlowChat::Whatsapp::Renderer.new(prompt, choices: choices, media: media).render
        type, content, _ = response

        result = instrument(Events::MESSAGE_SENT, {
          to: to,
          message_type: type.to_s,
          content_length: content.to_s.length,
          platform: :whatsapp
        }) do
          message_data = build_message_payload(response, to)
          send_message_payload(message_data)
        end

        if result
          message_sid = result["sid"]
          FlowChat.logger.debug { "Twilio::Client: Message sent successfully to #{to}, message_sid: #{message_sid}" }
        else
          FlowChat.logger.error { "Twilio::Client: Failed to send message to #{to}" }
        end

        result
      end

      # Send a text message
      # @param to [String] Phone number in E.164 format
      # @param text [String] Message text
      # @return [Hash] API response or nil on error
      def send_text(to, text)
        FlowChat.logger.debug { "Twilio::Client: Sending text message to #{to}" }
        send_message(to, text)
      end

      # Build message payload for Twilio API
      # This method is exposed so the gateway can use it for simulator mode
      def build_message_payload(response, to)
        type, content, options = response

        # Convert to WhatsApp address format
        whatsapp_to = "whatsapp:#{to}"
        whatsapp_from = "whatsapp:#{@config.phone_number}"

        case type
        when :text
          {
            From: whatsapp_from,
            To: whatsapp_to,
            Body: content
          }
        when :interactive_buttons
          # Twilio doesn't have native interactive buttons for WhatsApp
          # Fall back to text with numbered options
          buttons_text = content + "\n\n"
          options[:buttons].each_with_index do |button, index|
            buttons_text += "#{index + 1}. #{button[:title]}\n"
          end

          {
            From: whatsapp_from,
            To: whatsapp_to,
            Body: buttons_text.strip
          }
        when :interactive_list
          # Twilio doesn't have native interactive lists for WhatsApp
          # Fall back to text with numbered options
          list_text = content + "\n\n"
          options[:sections].each do |section|
            if section[:title]
              list_text += "#{section[:title]}:\n"
            end
            section[:rows].each_with_index do |row, index|
              list_text += "#{index + 1}. #{row[:title]}\n"
            end
            list_text += "\n"
          end

          {
            From: whatsapp_from,
            To: whatsapp_to,
            Body: list_text.strip
          }
        when :media_image, :media_document, :media_audio, :media_video
          payload = {
            From: whatsapp_from,
            To: whatsapp_to
          }

          if options[:url]
            payload[:MediaUrl] = options[:url]
          end

          if options[:caption] && content.present?
            payload[:Body] = content
          end

          payload
        else
          # Default to text message
          {
            From: whatsapp_from,
            To: whatsapp_to,
            Body: content.to_s
          }
        end
      end

      # Send image message
      # @param to [String] Phone number in E.164 format
      # @param image_url [String] Image URL
      # @param caption [String] Optional caption
      # @return [Hash] API response
      def send_image(to, image_url, caption = nil)
        FlowChat.logger.debug { "Twilio::Client: Sending image to #{to}" }
        media = {type: :image, url: image_url}
        send_message(to, caption, media: media)
      end

      # Send document message
      # @param to [String] Phone number in E.164 format
      # @param document_url [String] Document URL
      # @param caption [String] Optional caption
      # @return [Hash] API response
      def send_document(to, document_url, caption = nil)
        FlowChat.logger.debug { "Twilio::Client: Sending document to #{to}" }
        media = {type: :document, url: document_url}
        send_message(to, caption, media: media)
      end

      private

      # Send message payload to Twilio API
      # @param message_data [Hash] Message payload
      # @return [Hash] API response or nil on error
      def send_message_payload(message_data)
        to = message_data[:To]
        from = message_data[:From]

        FlowChat.logger.debug { "Twilio::Client: Sending API request from #{from} to #{to}" }

        uri = URI(@config.messages_url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri)

        # Set authentication header
        auth_string = Base64.strict_encode64("#{@config.account_sid}:#{@config.auth_token}")
        request["Authorization"] = "Basic #{auth_string}"
        request["Content-Type"] = "application/x-www-form-urlencoded"

        # Convert hash to form data
        request.body = URI.encode_www_form(message_data)

        FlowChat.logger.debug { "Twilio::Client: Making HTTP request to Twilio API" }
        response = http.request(request)

        if response.is_a?(Net::HTTPSuccess) || response.is_a?(Net::HTTPCreated)
          result = JSON.parse(response.body)
          FlowChat.logger.debug { "Twilio::Client: API request successful - response: #{result}" }
          result
        else
          FlowChat.logger.error { "Twilio::Client: API request failed - #{response.code}: #{response.body}" }
          nil
        end
      rescue Net::OpenTimeout, Net::ReadTimeout => network_error
        # Let network timeouts bubble up for proper error handling
        FlowChat.logger.error { "Twilio::Client: Network timeout: #{network_error.class.name}: #{network_error.message}" }
        raise network_error
      rescue => error
        FlowChat.logger.error { "Twilio::Client: API request exception: #{error.class.name}: #{error.message}" }
        nil
      end
    end
  end
end

require "net/http"
require "json"
require "uri"
require "tempfile"
require "securerandom"

module FlowChat
  module Whatsapp
    class Client
      def initialize(config)
        @config = config
        FlowChat.logger.info { "WhatsApp::Client: Initialized WhatsApp client for phone_number_id: #{@config.phone_number_id}" }
        FlowChat.logger.debug { "WhatsApp::Client: API base URL: #{FlowChat::Config.whatsapp.api_base_url}" }
      end

      # Send a message to a WhatsApp number
      # @param to [String] Phone number in E.164 format
      # @param response [Array] FlowChat response array [type, content, options]
      # @return [Hash] API response or nil on error
      def send_message(to, response)
        type, content, options = response
        FlowChat.logger.info { "WhatsApp::Client: Sending #{type} message to #{to}" }
        FlowChat.logger.debug { "WhatsApp::Client: Message content: '#{content.to_s.truncate(100)}'" }
        
        message_data = build_message_payload(response, to)
        result = send_message_payload(message_data)
        
        if result
          FlowChat.logger.info { "WhatsApp::Client: Message sent successfully to #{to}, message_id: #{result.dig('messages', 0, 'id')}" }
        else
          FlowChat.logger.error { "WhatsApp::Client: Failed to send message to #{to}" }
        end
        
        result
      end

      # Send a text message
      # @param to [String] Phone number in E.164 format
      # @param text [String] Message text
      # @return [Hash] API response or nil on error
      def send_text(to, text)
        FlowChat.logger.debug { "WhatsApp::Client: Sending text message to #{to}" }
        send_message(to, [:text, text, {}])
      end

      # Send interactive buttons
      # @param to [String] Phone number in E.164 format
      # @param text [String] Message text
      # @param buttons [Array] Array of button hashes with :id and :title
      # @return [Hash] API response or nil on error
      def send_buttons(to, text, buttons)
        FlowChat.logger.debug { "WhatsApp::Client: Sending interactive buttons to #{to} with #{buttons.size} buttons" }
        send_message(to, [:interactive_buttons, text, {buttons: buttons}])
      end

      # Send interactive list
      # @param to [String] Phone number in E.164 format
      # @param text [String] Message text
      # @param sections [Array] List sections
      # @param button_text [String] Button text (default: "Choose")
      # @return [Hash] API response or nil on error
      def send_list(to, text, sections, button_text = "Choose")
        total_items = sections.sum { |section| section[:rows]&.size || 0 }
        FlowChat.logger.debug { "WhatsApp::Client: Sending interactive list to #{to} with #{sections.size} sections, #{total_items} total items" }
        send_message(to, [:interactive_list, text, {sections: sections, button_text: button_text}])
      end

      # Send a template message
      # @param to [String] Phone number in E.164 format
      # @param template_name [String] Template name
      # @param components [Array] Template components
      # @param language [String] Language code (default: "en_US")
      # @return [Hash] API response or nil on error
      def send_template(to, template_name, components = [], language = "en_US")
        FlowChat.logger.debug { "WhatsApp::Client: Sending template '#{template_name}' to #{to} in #{language}" }
        send_message(to, [:template, "", {
          template_name: template_name,
          components: components,
          language: language
        }])
      end

      # Send image message
      # @param to [String] Phone number in E.164 format
      # @param image_url_or_id [String] Image URL or WhatsApp media ID
      # @param caption [String] Optional caption
      # @param mime_type [String] Optional MIME type for URLs (e.g., 'image/jpeg')
      # @return [Hash] API response
      def send_image(to, image_url_or_id, caption = nil, mime_type = nil)
        FlowChat.logger.debug { "WhatsApp::Client: Sending image to #{to} - #{url?(image_url_or_id) ? 'URL' : 'Media ID'}" }
        send_media_message(to, :image, image_url_or_id, caption: caption, mime_type: mime_type)
      end

      # Send document message
      # @param to [String] Phone number in E.164 format
      # @param document_url_or_id [String] Document URL or WhatsApp media ID
      # @param caption [String] Optional caption
      # @param filename [String] Optional filename
      # @param mime_type [String] Optional MIME type for URLs (e.g., 'application/pdf')
      # @return [Hash] API response
      def send_document(to, document_url_or_id, caption = nil, filename = nil, mime_type = nil)
        filename ||= extract_filename_from_url(document_url_or_id) if url?(document_url_or_id)
        FlowChat.logger.debug { "WhatsApp::Client: Sending document to #{to} - filename: #{filename}" }
        send_media_message(to, :document, document_url_or_id, caption: caption, filename: filename, mime_type: mime_type)
      end

      # Send video message
      # @param to [String] Phone number in E.164 format
      # @param video_url_or_id [String] Video URL or WhatsApp media ID
      # @param caption [String] Optional caption
      # @param mime_type [String] Optional MIME type for URLs (e.g., 'video/mp4')
      # @return [Hash] API response
      def send_video(to, video_url_or_id, caption = nil, mime_type = nil)
        FlowChat.logger.debug { "WhatsApp::Client: Sending video to #{to}" }
        send_media_message(to, :video, video_url_or_id, caption: caption, mime_type: mime_type)
      end

      # Send audio message
      # @param to [String] Phone number in E.164 format
      # @param audio_url_or_id [String] Audio URL or WhatsApp media ID
      # @param mime_type [String] Optional MIME type for URLs (e.g., 'audio/mpeg')
      # @return [Hash] API response
      def send_audio(to, audio_url_or_id, mime_type = nil)
        FlowChat.logger.debug { "WhatsApp::Client: Sending audio to #{to}" }
        send_media_message(to, :audio, audio_url_or_id, mime_type: mime_type)
      end

      # Send sticker message
      # @param to [String] Phone number in E.164 format
      # @param sticker_url_or_id [String] Sticker URL or WhatsApp media ID
      # @param mime_type [String] Optional MIME type for URLs (e.g., 'image/webp')
      # @return [Hash] API response
      def send_sticker(to, sticker_url_or_id, mime_type = nil)
        FlowChat.logger.debug { "WhatsApp::Client: Sending sticker to #{to}" }
        send_media_message(to, :sticker, sticker_url_or_id, mime_type: mime_type)
      end

      # Upload media file and return media ID
      # @param file_path_or_io [String, IO] File path or IO object
      # @param mime_type [String] MIME type of the file (required)
      # @param filename [String] Optional filename for the upload
      # @return [String] Media ID
      # @raise [StandardError] If upload fails
      def upload_media(file_path_or_io, mime_type, filename = nil)
        FlowChat.logger.info { "WhatsApp::Client: Uploading media file - type: #{mime_type}, filename: #{filename}" }
        
        raise ArgumentError, "mime_type is required" if mime_type.nil? || mime_type.empty?

        if file_path_or_io.is_a?(String)
          # File path
          raise ArgumentError, "File not found: #{file_path_or_io}" unless File.exist?(file_path_or_io)
          filename ||= File.basename(file_path_or_io)
          file_size = File.size(file_path_or_io)
          FlowChat.logger.debug { "WhatsApp::Client: Uploading file from path: #{file_path_or_io} (#{file_size} bytes)" }
          file = File.open(file_path_or_io, "rb")
        else
          # IO object
          file = file_path_or_io
          filename ||= "upload"
          FlowChat.logger.debug { "WhatsApp::Client: Uploading file from IO object" }
        end

        # Upload directly via HTTP
        uri = URI("#{FlowChat::Config.whatsapp.api_base_url}/#{@config.phone_number_id}/media")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        FlowChat.logger.debug { "WhatsApp::Client: Uploading to #{uri}" }

        # Prepare multipart form data
        boundary = "----WebKitFormBoundary#{SecureRandom.hex(16)}"

        form_data = []
        form_data << "--#{boundary}"
        form_data << 'Content-Disposition: form-data; name="messaging_product"'
        form_data << ""
        form_data << "whatsapp"

        form_data << "--#{boundary}"
        form_data << "Content-Disposition: form-data; name=\"file\"; filename=\"#{filename}\""
        form_data << "Content-Type: #{mime_type}"
        form_data << ""
        form_data << file.read

        form_data << "--#{boundary}"
        form_data << 'Content-Disposition: form-data; name="type"'
        form_data << ""
        form_data << mime_type

        form_data << "--#{boundary}--"

        body = form_data.join("\r\n")

        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{@config.access_token}"
        request["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
        request.body = body

        response = http.request(request)

        if response.is_a?(Net::HTTPSuccess)
          data = JSON.parse(response.body)
          media_id = data["id"]
          if media_id
            FlowChat.logger.info { "WhatsApp::Client: Media upload successful - media_id: #{media_id}" }
            media_id
          else
            FlowChat.logger.error { "WhatsApp::Client: Media upload failed - no media_id in response: #{data}" }
            raise StandardError, "Failed to upload media: #{data}"
          end
        else
          FlowChat.logger.error { "WhatsApp::Client: Media upload error - #{response.code}: #{response.body}" }
          raise StandardError, "Media upload failed: #{response.body}"
        end
      rescue => error
        FlowChat.logger.error { "WhatsApp::Client: Media upload exception: #{error.class.name}: #{error.message}" }
        raise
      ensure
        file&.close if file_path_or_io.is_a?(String)
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
            text: {body: content}
          }
        when :interactive_buttons
          interactive_payload = {
            type: "button",
            body: {text: content},
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

          # Add header if provided (for media support)
          if options[:header]
            interactive_payload[:header] = options[:header]
          end

          {
            messaging_product: "whatsapp",
            to: to,
            type: "interactive",
            interactive: interactive_payload
          }
        when :interactive_list
          {
            messaging_product: "whatsapp",
            to: to,
            type: "interactive",
            interactive: {
              type: "list",
              body: {text: content},
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
              language: {code: options[:language] || "en_US"},
              components: options[:components] || []
            }
          }
        when :media_image
          {
            messaging_product: "whatsapp",
            to: to,
            type: "image",
            image: build_media_object(options)
          }
        when :media_document
          {
            messaging_product: "whatsapp",
            to: to,
            type: "document",
            document: build_media_object(options)
          }
        when :media_audio
          {
            messaging_product: "whatsapp",
            to: to,
            type: "audio",
            audio: build_media_object(options)
          }
        when :media_video
          {
            messaging_product: "whatsapp",
            to: to,
            type: "video",
            video: build_media_object(options)
          }
        when :media_sticker
          {
            messaging_product: "whatsapp",
            to: to,
            type: "sticker",
            sticker: build_media_object(options)
          }
        else
          # Default to text message
          {
            messaging_product: "whatsapp",
            to: to,
            type: "text",
            text: {body: content.to_s}
          }
        end
      end

      # Get media URL from media ID
      # @param media_id [String] Media ID from WhatsApp
      # @return [String] Media URL or nil on error
      def get_media_url(media_id)
        uri = URI("#{FlowChat::Config.whatsapp.api_base_url}/#{media_id}")
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

      # Get MIME type from URL without downloading (HEAD request)
      def get_media_mime_type(url)
        require "net/http"

        uri = URI(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == "https")

        # Use HEAD request to get headers without downloading content
        response = http.head(uri.path)
        response["content-type"]
      rescue => e
        Rails.logger.warn "Could not detect MIME type for #{url}: #{e.message}"
        nil
      end

      private

      # Build media object for WhatsApp API, handling both URLs and media IDs
      # @param options [Hash] Options containing url/id, caption, filename
      # @return [Hash] Media object for WhatsApp API
      def build_media_object(options)
        media_obj = {}

        # Handle URL or ID
        if options[:url]
          # Use URL directly
          media_obj[:link] = options[:url]
        elsif options[:id]
          # Use provided media ID directly
          media_obj[:id] = options[:id]
        end

        # Add optional fields
        media_obj[:caption] = options[:caption] if options[:caption]
        media_obj[:filename] = options[:filename] if options[:filename]

        media_obj
      end

      # Check if input is a URL or file path/media ID
      def url?(input)
        input.to_s.start_with?("http://", "https://")
      end

      # Extract filename from URL
      def extract_filename_from_url(url)
        uri = URI(url)
        filename = File.basename(uri.path)
        filename.empty? ? "document" : filename
      rescue
        "document"
      end

      # Send message payload to WhatsApp API
      # @param message_data [Hash] Message payload
      # @return [Hash] API response or nil on error
      def send_message_payload(message_data)
        to = message_data[:to]
        message_type = message_data[:type]
        
        FlowChat.logger.debug { "WhatsApp::Client: Sending API request to #{to} - type: #{message_type}" }
        
        uri = URI("#{FlowChat::Config.whatsapp.api_base_url}/#{@config.phone_number_id}/messages")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{@config.access_token}"
        request["Content-Type"] = "application/json"
        request.body = message_data.to_json

        FlowChat.logger.debug { "WhatsApp::Client: Making HTTP request to WhatsApp API" }
        response = http.request(request)

        if response.is_a?(Net::HTTPSuccess)
          result = JSON.parse(response.body)
          FlowChat.logger.debug { "WhatsApp::Client: API request successful - response: #{result}" }
          result
        else
          FlowChat.logger.error { "WhatsApp::Client: API request failed - #{response.code}: #{response.body}" }
          nil
        end
      rescue Net::OpenTimeout, Net::ReadTimeout => network_error
        # Let network timeouts bubble up for proper error handling
        FlowChat.logger.error { "WhatsApp::Client: Network timeout: #{network_error.class.name}: #{network_error.message}" }
        raise network_error
      rescue => error
        FlowChat.logger.error { "WhatsApp::Client: API request exception: #{error.class.name}: #{error.message}" }
        nil
      end

      def send_media_message(to, media_type, url_or_id, caption: nil, filename: nil, mime_type: nil)
        media_object = if url?(url_or_id)
          {link: url_or_id}
        else
          {id: url_or_id}
        end

        # Add caption if provided (stickers don't support captions)
        media_object[:caption] = caption if caption && media_type != :sticker

        # Add filename for documents
        media_object[:filename] = filename if filename && media_type == :document

        message = {
          :messaging_product => "whatsapp",
          :to => to,
          :type => media_type.to_s,
          media_type.to_s => media_object
        }

        send_message_payload(message)
      end
    end
  end
end

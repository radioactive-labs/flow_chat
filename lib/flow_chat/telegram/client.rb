require "net/http"
require "json"
require "uri"

module FlowChat
  module Telegram
    class Client
      include FlowChat::Instrumentation

      def initialize(config)
        @config = config
        FlowChat.logger.info { "Telegram::Client: Initialized Telegram client" }
      end

      # Main send_message method matching FlowChat pattern
      def send_message(chat_id, prompt, choices: nil, media: nil)
        FlowChat.logger.info { "Telegram::Client: Sending message to chat #{chat_id}" }

        response = FlowChat::Telegram::Renderer.new(prompt, choices: choices, media: media).render
        type, content, options = response

        case type
        when :text
          send_text(chat_id, content)
        when :inline_keyboard
          send_text_with_keyboard(chat_id, content, options[:keyboard])
        when :photo
          send_photo(chat_id, options[:url], caption: content)
        when :photo_with_keyboard
          send_photo_with_keyboard(chat_id, options[:url], caption: content, keyboard: options[:keyboard])
        when :document
          send_document(chat_id, options[:url], caption: content)
        when :video
          send_video(chat_id, options[:url], caption: content)
        when :audio
          send_audio(chat_id, options[:url], caption: content)
        when :voice
          send_voice(chat_id, options[:url])
        else
          send_text(chat_id, content.to_s)
        end
      end

      def send_text(chat_id, text, parse_mode: "HTML")
        api_request("sendMessage", {
          chat_id: chat_id,
          text: text,
          parse_mode: parse_mode
        }.compact)
      end

      def send_text_with_keyboard(chat_id, text, keyboard, parse_mode: "HTML")
        api_request("sendMessage", {
          chat_id: chat_id,
          text: text,
          parse_mode: parse_mode,
          reply_markup: {inline_keyboard: keyboard}
        }.compact)
      end

      def send_photo(chat_id, photo_url_or_id, caption: nil)
        api_request("sendPhoto", {
          chat_id: chat_id,
          photo: photo_url_or_id,
          caption: caption
        }.compact)
      end

      def send_photo_with_keyboard(chat_id, photo_url_or_id, caption: nil, keyboard: nil)
        api_request("sendPhoto", {
          chat_id: chat_id,
          photo: photo_url_or_id,
          caption: caption,
          reply_markup: keyboard ? {inline_keyboard: keyboard} : nil
        }.compact)
      end

      def send_document(chat_id, document_url_or_id, caption: nil)
        api_request("sendDocument", {
          chat_id: chat_id,
          document: document_url_or_id,
          caption: caption
        }.compact)
      end

      def send_video(chat_id, video_url_or_id, caption: nil)
        api_request("sendVideo", {
          chat_id: chat_id,
          video: video_url_or_id,
          caption: caption
        }.compact)
      end

      def send_audio(chat_id, audio_url_or_id, caption: nil)
        api_request("sendAudio", {
          chat_id: chat_id,
          audio: audio_url_or_id,
          caption: caption
        }.compact)
      end

      def send_voice(chat_id, voice_url_or_id)
        api_request("sendVoice", {
          chat_id: chat_id,
          voice: voice_url_or_id
        })
      end

      def answer_callback_query(callback_query_id, text: nil, show_alert: false)
        api_request("answerCallbackQuery", {
          callback_query_id: callback_query_id,
          text: text,
          show_alert: show_alert
        }.compact)
      end

      def edit_message_text(chat_id, message_id, text, keyboard: nil, parse_mode: "HTML")
        api_request("editMessageText", {
          chat_id: chat_id,
          message_id: message_id,
          text: text,
          parse_mode: parse_mode,
          reply_markup: keyboard ? {inline_keyboard: keyboard} : nil
        }.compact)
      end

      def delete_message(chat_id, message_id)
        api_request("deleteMessage", {
          chat_id: chat_id,
          message_id: message_id
        })
      end

      # Send a chat action (e.g. typing indicator) to a Telegram chat.
      #
      # The action lasts ~5 seconds or until the next outbound message.
      # Valid actions per Telegram Bot API: "typing", "upload_photo",
      # "record_video", "upload_video", "record_voice", "upload_voice",
      # "upload_document", "choose_sticker", "find_location",
      # "record_video_note", "upload_video_note".
      #
      # @param chat_id [Integer, String] the target chat id
      # @param action [String] the chat action to broadcast (default: "typing")
      # @return [Hash] parsed Telegram API response
      def send_chat_action(chat_id, action: "typing")
        api_request("sendChatAction", chat_id: chat_id, action: action)
      end

      # Show a typing indicator in a Telegram chat.
      #
      # Convenience wrapper around `send_chat_action(chat_id, action: "typing")`.
      # The indicator lasts ~5 seconds or until the next outbound message;
      # there is no stop-typing call.
      #
      # @param chat_id [Integer, String] the target chat id
      # @return [Hash] parsed Telegram API response
      def indicate_typing(chat_id)
        send_chat_action(chat_id, action: "typing")
      end

      # Webhook management
      def set_webhook(url, secret_token: nil, allowed_updates: nil)
        api_request("setWebhook", {
          url: url,
          secret_token: secret_token,
          allowed_updates: allowed_updates || ["message", "callback_query"]
        }.compact)
      end

      def delete_webhook
        api_request("deleteWebhook")
      end

      def get_webhook_info
        api_request("getWebhookInfo")
      end

      def get_me
        api_request("getMe")
      end

      # Get file metadata (including file_path) for an inbound file_id
      def get_file(file_id)
        api_request("getFile", {file_id: file_id})
      end

      # Build the download URL for an inbound file_id
      def file_url(file_id)
        file_path = get_file(file_id).dig("result", "file_path")
        return nil unless file_path

        "https://api.telegram.org/file/bot#{@config.bot_token}/#{file_path}"
      end

      # Download the raw bytes for an inbound file_id
      def download_file(file_id)
        url = file_url(file_id)
        return nil unless url

        uri = URI(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        response = http.get(uri.request_uri)

        if response.is_a?(Net::HTTPSuccess)
          response.body
        else
          FlowChat.logger.error { "Telegram::Client: File download error: #{response.code}" }
          nil
        end
      end

      private

      def api_request(method, params = {})
        uri = URI("#{@config.api_base_url}/#{method}")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request.body = params.to_json

        FlowChat.logger.debug { "Telegram::Client: API request to #{method}" }

        response = http.request(request)
        result = JSON.parse(response.body)

        if result["ok"]
          FlowChat.logger.debug { "Telegram::Client: API request successful" }
        else
          FlowChat.logger.error { "Telegram::Client: API error - #{result["description"]}" }
          report_api_error(
            "Telegram API error: #{result["description"]}",
            api_method: method,
            error_code: result["error_code"],
            error_description: result["description"],
            chat_id: params[:chat_id]
          )
        end

        result
      rescue Net::OpenTimeout, Net::ReadTimeout => network_error
        FlowChat.logger.error { "Telegram::Client: Network timeout: #{network_error.class.name}: #{network_error.message}" }
        raise network_error
      rescue => error
        FlowChat.logger.error { "Telegram::Client: API request exception: #{error.class.name}: #{error.message}" }
        report_api_error(
          "Telegram API request exception: #{error.class.name}",
          api_method: method,
          error: error,
          chat_id: params[:chat_id]
        )
        {"ok" => false, "description" => error.message}
      end

      def report_api_error(message, api_method: nil, error_code: nil, error_description: nil, error: nil, chat_id: nil)
        FlowChat::Instrumentation.report_api_error(
          message,
          error: error,
          platform: :telegram,
          bot_id: @config.bot_id,
          api_method: api_method,
          error_code: error_code,
          error_description: error_description,
          chat_id: chat_id
        )
      end
    end
  end
end

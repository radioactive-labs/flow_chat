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
        end

        result
      end
    end
  end
end

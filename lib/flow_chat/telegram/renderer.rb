module FlowChat
  module Telegram
    class Renderer
      attr_reader :message, :choices, :media

      def initialize(message, choices: nil, media: nil)
        @message = message
        @choices = choices
        @media = media
      end

      def render
        if media && choices
          build_media_with_keyboard
        elsif media
          build_media_message
        elsif choices
          build_keyboard_message
        else
          build_text_message
        end
      end

      private

      def build_text_message
        [:text, escape_html(message), {}]
      end

      def build_keyboard_message
        validate_choices!
        keyboard = build_inline_keyboard(choices)
        [:inline_keyboard, escape_html(message), {keyboard: keyboard}]
      end

      def build_media_message
        media_type = media[:type] || :photo
        url = media[:url] || media[:file_id]

        case media_type.to_sym
        when :photo
          [:photo, message, {url: url}]
        when :document
          [:document, message, {url: url, filename: media[:filename]}]
        when :video
          [:video, message, {url: url}]
        when :audio
          [:audio, message, {url: url}]
        when :voice
          [:voice, message, {url: url}]
        else
          # Fallback to text for unsupported types
          [:text, escape_html(message), {}]
        end
      end

      def build_media_with_keyboard
        validate_choices!
        keyboard = build_inline_keyboard(choices)
        media_type = media[:type] || :photo
        url = media[:url] || media[:file_id]

        [:photo_with_keyboard, message, {
          url: url,
          keyboard: keyboard,
          media_type: media_type.to_sym
        }]
      end

      def build_inline_keyboard(choice_hash)
        buttons = choice_hash.map do |key, value|
          {
            text: truncate_text(value.to_s, 64),
            callback_data: key.to_s[0, 64]
          }
        end

        # Layout: 2 buttons per row for <=4 choices, 1 per row for >4
        if buttons.length <= 4
          buttons.each_slice(2).to_a
        else
          buttons.map { |b| [b] }
        end
      end

      def validate_choices!
        unless choices.is_a?(Hash)
          raise ArgumentError, "choices must be a Hash"
        end
      end

      def truncate_text(text, length)
        return text if text.length <= length
        text[0, length - 3] + "..."
      end

      def escape_html(text)
        return "" if text.nil?
        text.to_s
          .gsub("&", "&amp;")
          .gsub("<", "&lt;")
          .gsub(">", "&gt;")
      end
    end
  end
end

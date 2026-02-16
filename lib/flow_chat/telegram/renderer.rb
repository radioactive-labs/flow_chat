require "flow_chat/renderers/markdown_support"

module FlowChat
  module Telegram
    class Renderer
      include FlowChat::Renderers::MarkdownSupport

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
        [:text, to_html(message), {}]
      end

      def build_keyboard_message
        validate_choices!
        keyboard = build_inline_keyboard(choices)
        [:inline_keyboard, to_html(message), {keyboard: keyboard}]
      end

      def build_media_message
        media_type = media[:type] || :photo
        url = media[:url] || media[:file_id]

        case media_type.to_sym
        when :photo
          [:photo, to_html(message), {url: url}]
        when :document
          [:document, to_html(message), {url: url, filename: media[:filename]}]
        when :video
          [:video, to_html(message), {url: url}]
        when :audio
          [:audio, to_html(message), {url: url}]
        when :voice
          [:voice, to_html(message), {url: url}]
        else
          # Fallback to text for unsupported types
          [:text, to_html(message), {}]
        end
      end

      def build_media_with_keyboard
        validate_choices!
        keyboard = build_inline_keyboard(choices)
        media_type = media[:type] || :photo
        url = media[:url] || media[:file_id]

        [:photo_with_keyboard, to_html(message), {
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

      # MarkdownSupport overrides for Telegram-specific behavior

      def allowed_tags
        # Tags supported by Telegram Bot API HTML mode
        # Note: p and br are allowed through sanitization but converted to newlines in post_process_html
        %w[b strong i em u s strike del a code pre blockquote p br]
      end

      def allowed_attributes
        %w[href]
      end

      def post_process_html(html)
        # Convert <p> tags to text with double newlines (Telegram doesn't support <p>)
        result = html.gsub(%r{<p>(.*?)</p>}m, '\1' + "\n\n")

        # Convert <br> and <br/> to newlines (Telegram doesn't support <br>)
        result = result.gsub(/<br\s*\/?>/, "\n")

        # Clean up excessive newlines
        result.gsub(/\n{3,}/, "\n\n").strip
      end
    end
  end
end

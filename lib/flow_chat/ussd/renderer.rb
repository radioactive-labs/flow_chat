module FlowChat
  module Ussd
    class Renderer
      attr_reader :prompt, :choices, :media

      def initialize(prompt, choices: nil, media: nil)
        @prompt = prompt
        @choices = choices
        @media = media
      end

      def render = build_prompt

      private

      def build_prompt
        parts = [build_media, prompt, build_choices].compact
        parts.join "\n\n"
      end

      def build_choices
        return unless choices.present?

        choices.map { |i, c| "#{i}. #{c}" }.join "\n"
      end

      def build_media
        return unless media.present?

        media_url = media[:url] || media[:path]
        media_type = media[:type] || :image

        # For USSD, we append the media URL to the message
        case media_type.to_sym
        when :image
          "📷 Image: #{media_url}"
        when :document
          "📄 Document: #{media_url}"
        when :audio
          "🎵 Audio: #{media_url}"
        when :video
          "🎥 Video: #{media_url}"
        when :sticker
          "😊 Sticker: #{media_url}"
        else
          "📎 Media: #{media_url}"
        end
      end
    end
  end
end

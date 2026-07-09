module FlowChat
  module Http
    class Renderer
      attr_reader :prompt, :choices, :media

      def initialize(prompt, choices: nil, media: nil)
        @prompt = prompt
        @choices = choices
        @media = media
      end

      def render = build_response

      private

      def build_response
        {
          message: prompt,
          choices: format_choices,
          media: format_media
        }.compact
      end

      def format_choices
        return unless choices.present?

        choices.map { |key, value| {key: key, value: value} }
      end

      def format_media
        return unless media.present?

        {
          url: media[:url],
          type: media[:type] || :image,
          caption: media[:caption]
        }.compact
      end
    end
  end
end

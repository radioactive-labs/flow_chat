module FlowChat
  module Ussd
    class Renderer
      attr_reader :prompt, :choices

      def initialize(prompt, choices)
        @prompt = prompt
        @choices = choices
      end

      def render = build_prompt

      private

      def build_prompt
        [prompt, build_choices].compact.join "\n\n"
      end

      def build_choices
        return unless choices.present?

        choices.map { |i, c| "#{i}. #{c}" }.join "\n"
      end
    end
  end
end

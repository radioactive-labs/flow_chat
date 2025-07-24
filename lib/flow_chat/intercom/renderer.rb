module FlowChat
  module Intercom
    class Renderer
      attr_reader :message, :choices, :media

      def initialize(message, choices: nil, media: nil)
        @message = message
        @choices = choices
        @media = media
      end

      def render
        if choices
          build_selection_message
        else
          build_text_message
        end
      end

      private

      def build_text_message
        [:text, message, {}]
      end

      def build_selection_message
        if choices.is_a?(Hash)
          build_interactive_message(choices)
        else
          raise ArgumentError, "choices must be a Hash"
        end
      end

      def build_interactive_message(choice_hash)
        # For Intercom, we'll present choices as a formatted text message
        # since Intercom doesn't have the same interactive elements as WhatsApp

        formatted_message = message.to_s

        unless formatted_message.empty?
          formatted_message += "\n\n"
        end

        # Add numbered choices
        formatted_message += "Please choose:\n"
        choice_hash.each_with_index do |(key, value), index|
          formatted_message += "#{index + 1}. #{value}\n"
        end

        formatted_message += "\nReply with the number of your choice."

        [:text, formatted_message, {choices: choice_hash}]
      end
    end
  end
end

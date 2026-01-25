require "kramdown"

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
        [:text, to_html(message), {}]
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

        [:text, to_html(formatted_message), {choices: choice_hash}]
      end

      def to_html(text)
        return "" if text.nil?

        html = Kramdown::Document.new(text.to_s).to_html.strip
        # Sanitize to only allow tags supported by Intercom messenger
        ActionController::Base.helpers.sanitize(
          html,
          tags: %w[p br b strong i em a ul ol li h1 h2 h3 h4 h5 h6],
          attributes: %w[href target]
        )
      end
    end
  end
end

require "twilio-ruby"

module FlowChat
  module Whatsapp
    class TwimlRenderer < Renderer
      def render
        # Get structured data from parent renderer
        type, content, options = super

        # Convert to TwiML
        response = ::Twilio::TwiML::MessagingResponse.new

        case type
        when :text
          response.message body: content
        when :interactive_buttons
          # Twilio doesn't have native interactive buttons for WhatsApp
          # Convert to text with numbered options
          text_with_options = build_text_with_numbered_buttons(content, options[:buttons])
          response.message body: text_with_options
        when :interactive_list
          # Twilio doesn't have native interactive lists for WhatsApp
          # Convert to text with numbered options
          text_with_options = build_text_with_numbered_list(content, options[:sections])
          response.message body: text_with_options
        when :media_image, :media_document, :media_audio, :media_video
          message_attrs = {}
          message_attrs[:media_url] = options[:url] if options[:url]

          if options[:caption] && !options[:caption].empty?
            response.message(message_attrs) { |m| m.body(options[:caption]) }
          else
            response.message(message_attrs)
          end
        else
          # Default to text message
          response.message body: content.to_s
        end

        response.to_s
      end

      private

      def build_text_with_numbered_buttons(content, buttons)
        text = content.to_s
        return text if buttons.nil? || buttons.empty?

        text += "\n\n"
        buttons.each_with_index do |button, index|
          text += "#{index + 1}. #{button[:title]}\n"
        end
        text.strip
      end

      def build_text_with_numbered_list(content, sections)
        text = content.to_s
        return text if sections.nil? || sections.empty?

        text += "\n\n"
        option_number = 1

        sections.each do |section|
          if section[:title]
            text += "#{section[:title]}:\n"
          end

          section[:rows].each do |row|
            text += "#{option_number}. #{row[:title]}\n"
            option_number += 1
          end

          text += "\n" unless section == sections.last
        end

        text.strip
      end
    end
  end
end

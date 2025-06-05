module FlowChat
  module Whatsapp
    class Renderer
      attr_reader :message, :choices, :media

      def initialize(message, choices: nil, media: nil)
        @message = message
        @choices = choices
        @media = media
      end

      def render
        if media
          build_media_message
        elsif choices
          build_selection_message
        else
          build_text_message
        end
      end

      private

      def build_text_message
        [:text, message, {}]
      end

      def build_media_message
        media_type = media[:type] || :image
        url = media[:url] || media[:path]
        filename = media[:filename]

        case media_type.to_sym
        when :image
          [:media_image, "", {url: url, caption: message}]
        when :document
          [:media_document, "", {url: url, caption: message, filename: filename}]
        when :audio
          [:media_audio, "", {url: url, caption: message}]
        when :video
          [:media_video, "", {url: url, caption: message}]
        when :sticker
          [:media_sticker, "", {url: url}] # Stickers don't support captions
        else
          raise ArgumentError, "Unsupported media type: #{media_type}"
        end
      end

      def build_selection_message
        # Determine the best way to present choices
        if choices.is_a?(Array)
          # Convert array to hash with index-based keys
          choice_hash = choices.each_with_index.to_h { |choice, index| [index.to_s, choice] }
          build_interactive_message(choice_hash)
        elsif choices.is_a?(Hash)
          build_interactive_message(choices)
        else
          raise ArgumentError, "choices must be an Array or Hash"
        end
      end

      def build_interactive_message(choice_hash)
        if choice_hash.length <= 3
          # Use buttons for 3 or fewer choices
          build_buttons_message(choice_hash)
        else
          # Use list for more than 3 choices
          build_list_message(choice_hash)
        end
      end

      def build_buttons_message(choices)
        buttons = choices.map do |key, value|
          {
            id: key.to_s,
            title: truncate_text(value.to_s, 20) # WhatsApp button titles have a 20 character limit
          }
        end

        [:interactive_buttons, message, {buttons: buttons}]
      end

      def build_list_message(choices)
        items = choices.map do |key, value|
          original_text = value.to_s
          truncated_title = truncate_text(original_text, 24)

          # If title was truncated, put full text in description (up to 72 chars)
          description = if original_text.length > 24
            truncate_text(original_text, 72)
          end

          {
            id: key.to_s,
            title: truncated_title,
            description: description
          }.compact
        end

        # If 10 or fewer items, use single section
        sections = if items.length <= 10
          [
            {
              title: "Options",
              rows: items
            }
          ]
        else
          # Paginate into multiple sections (max 10 items per section)
          items.each_slice(10).with_index.map do |section_items, index|
            start_num = (index * 10) + 1
            end_num = start_num + section_items.length - 1

            {
              title: "#{start_num}-#{end_num}",
              rows: section_items
            }
          end
        end

        [:interactive_list, message, {sections: sections}]
      end

      def truncate_text(text, length)
        return text if text.length <= length
        text[0, length - 3] + "..."
      end
    end
  end
end 
require "flow_chat/renderers/markdown_support"

module FlowChat
  module Messenger
    class Renderer
      include FlowChat::Renderers::MarkdownSupport

      attr_reader :message, :choices, :media

      def initialize(message, choices: nil, media: nil)
        @message = message
        @choices = choices
        @media = media
      end

      def render
        return build_attachment if media && choices.blank?

        case FlowChat::Meta::ChoiceLadder.rung_for(choice_count, limits)
        when :none then build_text
        when :quick_replies then build_quick_replies
        when :carousel then build_carousel
        when :numbered then build_text
        end
      end

      private

      # Instagram overrides both hooks: its own limits, and always_number
      # because its interactive surfaces render on mobile only.
      def limits
        FlowChat::Config.messenger
      end

      def always_number?
        false
      end

      def choice_count
        choices.is_a?(Hash) ? choices.length : 0
      end

      # Neither Messenger nor Instagram renders markup, so the prompt is
      # flattened rather than translated.
      def body
        text = to_plain_text(message)
        return text unless FlowChat::Meta::ChoiceLadder.numbers_in_body?(choice_count, limits, always_number: always_number?)

        "#{text}\n\n#{numbered_options}"
      end

      def numbered_options
        choices.values.map.with_index(1) { |label, i| "#{i}. #{label}" }.join("\n")
      end

      # Covers both the :none rung and the :numbered rung above the carousel
      # capacity: body already appends the numbered options when the ladder
      # calls for it, so there is nothing left for a separate method to add.
      def build_text
        [:text, body, {}]
      end

      def build_quick_replies
        replies = choices.map do |key, label|
          {
            content_type: "text",
            title: truncate_text(label.to_s, limits.max_quick_reply_title),
            payload: key.to_s
          }
        end

        [:quick_replies, body, {quick_replies: replies}]
      end

      # One option is one button, and buttons live on elements, so the options
      # are packed across elements rather than one element per option.
      def build_carousel
        elements = choices.each_slice(limits.max_buttons_per_element).map.with_index(1) do |slice, index|
          first = (index - 1) * limits.max_buttons_per_element + 1
          last = first + slice.length - 1

          {
            title: truncate_text("Options #{first} to #{last}", limits.max_element_title),
            buttons: slice.map do |key, label|
              {
                type: "postback",
                title: truncate_text(label.to_s, limits.max_button_title),
                payload: key.to_s
              }
            end
          }
        end

        [:carousel, body, {elements: elements}]
      end

      def build_attachment
        type = (media[:type] || :image).to_sym
        options = {type: type}
        options[:url] = media[:url] if media[:url]
        options[:attachment_id] = media[:id] if media[:id]

        [:attachment, to_plain_text(message), options]
      end

      def truncate_text(text, length)
        return text if text.length <= length
        text[0, length - 3] + "..."
      end
    end
  end
end

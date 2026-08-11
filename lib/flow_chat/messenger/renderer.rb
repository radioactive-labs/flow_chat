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

        result = case FlowChat::Meta::ChoiceLadder.rung_for(choice_count, limits)
        when :none then build_text
        when :quick_replies then build_quick_replies
        when :carousel then build_carousel
        when :numbered then build_text
        end

        attach_media(result)
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

      # Whether titles are numbered, and the enumeration order positions come
      # from, are both decided by FlowChat::ChoiceTitles over this same
      # `choices` hash - the choice mapper's ChoiceAliasBuilder.build call
      # goes through the same module over the same hash, so the two can
      # never disagree on which titles are shown or which ones are aliased.
      def build_quick_replies
        replies = FlowChat::ChoiceTitles.build(choices, limits.max_quick_reply_title).map do |key, _label, title, _truncated|
          {
            content_type: "text",
            title: title,
            payload: key
          }
        end

        [:quick_replies, body, {quick_replies: replies}]
      end

      # One option is one button, and buttons live on elements, so the options
      # are packed across elements rather than one element per option.
      #
      # FlowChat::ChoiceTitles.build runs once over the whole choice set,
      # before slicing into elements: both the ambiguity decision and the
      # resulting position numbers have to consider every choice together,
      # not each element's slice in isolation. Two different slices could
      # each hold a "Foo" that only collides once the whole set is in view,
      # and the numbering an element's buttons carry has to continue where
      # the previous element's left off (button 14 reads "14.", not "2." of
      # its own element) - both are only correct computed globally.
      def build_carousel
        numbered_choices = FlowChat::ChoiceTitles.build(choices, limits.max_button_title)

        elements = numbered_choices.each_slice(limits.max_buttons_per_element).map.with_index(1) do |slice, index|
          first = (index - 1) * limits.max_buttons_per_element + 1
          last = first + slice.length - 1

          {
            title: FlowChat::TextTruncator.truncate("Options #{first} to #{last}", limits.max_element_title),
            buttons: slice.map do |key, _label, title, _truncated|
              {
                type: "postback",
                title: title,
                payload: key
              }
            end
          }
        end

        [:carousel, body, {elements: elements}]
      end

      def build_attachment
        [:attachment, to_plain_text(message), media_attachment_options]
      end

      # Media is additive: it does not change which choice surface is used.
      # It rides along in options[:media] so the client can post it as its
      # own message ahead of whichever rung the choice count would render
      # with no media at all.
      def attach_media(result)
        return result unless media

        type, content, options = result
        [type, content, options.merge(media: media_attachment_options)]
      end

      def media_attachment_options
        type = (media[:type] || :image).to_sym
        options = {type: type}
        options[:url] = media[:url] if media[:url]
        options[:attachment_id] = media[:id] if media[:id]
        options
      end
    end
  end
end

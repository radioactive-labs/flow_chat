require "flow_chat/renderers/markdown_support"

module FlowChat
  module Intercom
    class Renderer
      include FlowChat::Renderers::MarkdownSupport

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
        link, options = render_media
        [:text, to_html(message.to_s + link), options]
      end

      def build_selection_message
        if choices.is_a?(Hash)
          build_interactive_message(choices)
        else
          raise ArgumentError, "choices must be a Hash"
        end
      end

      def build_interactive_message(choice_hash)
        # Intercom does support real buttons (message_type: "quick_reply"), sent
        # separately below by the client since body is forbidden on that message
        # type. The numbered list stays in this comment regardless, for two
        # reasons: whether a tap's quick_reply_uuid actually reaches the webhook
        # where we expect it is unverified, so the numbered text plus the
        # existing text/number matcher is what makes a reply resolve if it
        # doesn't; and it mirrors Instagram's always_number? in this gem, which
        # lists options in the body for the same reason - the interactive
        # surface doesn't reach every viewer.
        formatted_message = message.to_s

        unless formatted_message.empty?
          formatted_message += "\n\n"
        end

        # Add numbered choices
        formatted_message += "Please choose:\n"
        choice_hash.each_with_index do |(key, value), index|
          formatted_message += "#{index + 1}. #{value}\n"
        end

        link, options = render_media
        reply_options = choice_hash.map { |key, value| {uuid: key.to_s, text: value.to_s} }
        [:text, to_html(formatted_message + link), options.merge(choices: choice_hash, reply_options: reply_options)]
      end

      # Intercom's admin reply only takes real attachments as image URLs
      # (attachment_urls, documented specifically for images, max 10). Any
      # other media type with a url - document, video, audio, sticker -
      # becomes a markdown link in the body instead, since attachment_urls
      # is documented for images and a non-image URL there may not render.
      # An id with no url is another platform's upload handle (a WhatsApp
      # media id, say) and means nothing to Intercom, so it is logged and
      # dropped rather than raised: a multi-platform flow legitimately sets
      # an id for whichever platform uploaded it, and one platform lacking
      # the media should not fail the whole turn.
      #
      # Returns [markdown_suffix, options] - the suffix is appended to the
      # message before markdown-to-HTML conversion so a link goes through
      # the same sanitizer and allowed_tags as the rest of the body.
      def render_media
        return ["", {}] unless media

        url = media[:url]
        media_type = (media[:type] || :image).to_sym

        unless url
          FlowChat.logger.warn { "Intercom::Renderer: media id #{media[:id].inspect} is another platform's upload handle and means nothing to Intercom (no url given); sending the message without it" }
          return ["", {}]
        end

        if media_type == :image
          ["", {attachment_urls: [url]}]
        else
          label = media[:filename] || media_type.to_s.capitalize
          ["\n\n[#{label}](#{url})", {}]
        end
      end

      # MarkdownSupport overrides for Intercom-specific behavior

      def allowed_tags
        # Tags supported by Intercom messenger
        %w[p br b strong i em a ul ol li h1 h2 h3 h4 h5 h6]
      end

      def allowed_attributes
        %w[href target]
      end
    end
  end
end

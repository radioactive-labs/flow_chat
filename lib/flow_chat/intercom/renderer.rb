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

      # Choices are a numbered list rather than Intercom's own quick replies,
      # and that is a decision rather than an oversight. Intercom does document
      # reply_options with message_type "quick_reply" on an admin reply, and it
      # was built here and reverted. Three reasons, in the order they matter:
      #
      # - The uuid of a clicked option comes back as quick_reply_option_uuid,
      #   and only if the Intercom app is set to the *Unstable* API version.
      #   Webhooks inherit that setting, so an app on a stable version receives
      #   no metadata at all. Requiring an unstable API version for something as
      #   basic as reading which option was chosen is not a thing a library can
      #   ask of its users.
      # - body is forbidden on a quick_reply, so a choice screen becomes two
      #   conversation parts: one for the prompt, one for the buttons. In an
      #   inbox a human reads, that doubles the length of every flow.
      # - Intercom's own community reports the endpoint returning errors for
      #   this shape.
      #
      # A numbered list needs none of that and works on every API version. If
      # Intercom stabilises quick replies, the git history has the
      # implementation; check those three things before restoring it.
      def build_interactive_message(choice_hash)
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

        link, options = render_media
        [:text, to_html(formatted_message + link), options.merge(choices: choice_hash)]
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

require "flow_chat/renderers/markdown_support"

module FlowChat
  module Whatsapp
    class Renderer
      include FlowChat::Renderers::MarkdownSupport

      # Meta: "up to 10 sections, with up to 10 rows for all sections combined".
      MAX_LIST_ROWS = 10
      MAX_BUTTONS = 3

      # WhatsApp button and list row title limits. The choice mapper reads
      # these too, to alias the truncated title it knows this renderer will
      # display for a given choice count.
      BUTTON_TITLE_LENGTH = 20
      LIST_ROW_TITLE_LENGTH = 24

      attr_reader :message, :choices, :media

      def initialize(message, choices: nil, media: nil)
        @message = message
        @choices = choices
        @media = media
      end

      def render
        if media && choices
          build_selection_message_with_media
        elsif media
          build_media_message
        elsif choices
          build_selection_message
        else
          build_text_message
        end
      end

      private

      def build_text_message
        [:text, to_whatsapp(message), {}]
      end

      def formatted_message
        to_whatsapp(message)
      end

      def formatted_caption
        message.present? ? to_whatsapp(message) : nil
      end

      # @param caption [String, nil] defaults to the prompt text. Pass nil when
      #   this media is a companion sent ahead of a choice message: the prompt
      #   is about to appear in that message's body, and a caption here would
      #   just duplicate it.
      def build_media_message(caption: formatted_caption)
        media_type = media[:type] || :image
        url = media[:url]
        id = media[:id]
        filename = media[:filename]

        case media_type.to_sym
        when :image
          options = {}
          options[:url] = url if url
          options[:id] = id if id
          options[:caption] = caption if caption
          [:media_image, "", options]
        when :document
          options = {}
          options[:url] = url if url
          options[:id] = id if id
          options[:caption] = caption if caption
          options[:filename] = filename if filename
          [:media_document, "", options]
        when :audio
          options = {}
          options[:url] = url if url
          options[:id] = id if id
          options[:caption] = caption if caption
          [:media_audio, "", options]
        when :video
          options = {}
          options[:url] = url if url
          options[:id] = id if id
          options[:caption] = caption if caption
          [:media_video, "", options]
        when :sticker
          options = {}
          options[:url] = url if url
          options[:id] = id if id
          [:media_sticker, "", options] # Stickers don't support captions
        when :template
          [:template, "", {
            template_name: media[:template_name],
            components: media[:components] || [],
            language: media[:language] || "en_US"
          }]
        else
          raise ArgumentError, "Unsupported media type: #{media_type}"
        end
      end

      def build_selection_message
        if choices.is_a?(Hash)
          build_interactive_message(choices)
        else
          raise ArgumentError, "choices must be a Hash"
        end
      end

      # Media is additive: it does not change which choice surface is used.
      # 3 or fewer choices is the one case WhatsApp can carry both in a
      # single message (buttons with a media header), so that stays as is.
      # Above that, there is no interactive surface left that can carry
      # media - Meta's interactive message reference documents header.type:
      # text for list messages; image, video and document headers are only
      # defined for button messages - so the media goes out as its own
      # message and the list or numbered rendering follows unchanged.
      def build_selection_message_with_media
        choice_hash = normalized_choices

        if choice_hash.length <= MAX_BUTTONS
          build_buttons_message_with_media(choice_hash)
        else
          type, content, options = build_interactive_message(choice_hash)
          [type, content, options.merge(media: build_media_message(caption: nil))]
        end
      end

      def normalized_choices
        if choices.is_a?(Array)
          choices.each_with_index.to_h { |choice, index| [index.to_s, choice] }
        elsif choices.is_a?(Hash)
          choices
        else
          raise ArgumentError, "choices must be an Array or Hash"
        end
      end

      def build_interactive_message(choice_hash)
        if choice_hash.length <= MAX_BUTTONS
          build_buttons_message(choice_hash)
        elsif choice_hash.length <= MAX_LIST_ROWS
          build_list_message(choice_hash)
        else
          build_numbered_message(choice_hash)
        end
      end

      # Whether titles are numbered, and the enumeration order positions come
      # from, are both decided by FlowChat::ChoiceTitles over this same
      # `choices` hash - the choice mapper's ChoiceAliasBuilder.build call
      # goes through the same module over the same hash, so the two can
      # never disagree on which titles are shown or which ones are aliased.
      def build_buttons_message(choices)
        buttons = FlowChat::ChoiceTitles.build(choices, BUTTON_TITLE_LENGTH).map do |key, _label, title, _truncated|
          {id: key, title: title}
        end

        [:interactive_buttons, formatted_message, {buttons: buttons}]
      end

      def build_buttons_message_with_media(choices)
        buttons = FlowChat::ChoiceTitles.build(choices, BUTTON_TITLE_LENGTH).map do |key, _label, title, _truncated|
          {id: key, title: title}
        end

        # Build media header
        header = build_media_header

        [:interactive_buttons, formatted_message, {buttons: buttons, header: header}]
      end

      def build_media_header
        media_type = media[:type] || :image
        url = media[:url]
        filename = media[:filename]

        case media_type.to_sym
        when :image
          {
            type: "image",
            image: {link: url}
          }
        when :video
          {
            type: "video",
            video: {link: url}
          }
        when :document
          header_doc = {link: url}
          header_doc[:filename] = filename if filename
          {
            type: "document",
            document: header_doc
          }
        when :text
          {
            type: "text",
            text: url # For text headers, url contains the text
          }
        else
          raise ArgumentError, "Unsupported header media type: #{media_type}. Supported types for button headers: image, video, document, text"
        end
      end

      # See the comment on build_buttons_message: numbering and position both
      # come from FlowChat::ChoiceTitles over this same `choices` hash.
      #
      # The description (a longer, secondary line WhatsApp renders below the
      # title, up to 72 chars) is not numbered: nothing resolves a typed
      # description back to a choice, only the title and the position are
      # aliased, so a prefix there would just be noise. It is populated
      # whenever the title's own label portion didn't fit - whether that's
      # because the label alone exceeds the cap, or because a position
      # prefix ate into the room left for it.
      def build_list_message(choices)
        items = FlowChat::ChoiceTitles.build(choices, LIST_ROW_TITLE_LENGTH).map do |key, label, title, truncated|
          description = FlowChat::TextTruncator.truncate(label, 72) if truncated

          {
            id: key,
            title: title,
            description: description
          }.compact
        end

        [:interactive_list, formatted_message, {sections: [{title: "Options", rows: items}]}]
      end

      # Above the row cap there is no interactive surface left, so the options go
      # in the body and the user types a number. The choice mapper stores the
      # positions for this rung so the digit resolves to the original key.
      def build_numbered_message(choices)
        numbered = choices.values.map.with_index(1) { |label, i| "#{i}. #{label}" }.join("\n")

        [:text, "#{formatted_message}\n\n#{numbered}", {}]
      end

      # Convert text to WhatsApp format
      # Processes markdown through HTML, then converts HTML tags to WhatsApp syntax
      def to_whatsapp(text)
        return "" if text.nil?

        # Pre-process: handle markdown features not supported by standard kramdown
        processed = preprocess_markdown(text.to_s)

        # Convert markdown to HTML
        html = Kramdown::Document.new(processed, **kramdown_options).to_html.strip
        html_to_whatsapp(html)
      end

      # Handle markdown features not natively supported by kramdown
      def preprocess_markdown(text)
        result = text.dup

        # Convert fenced code blocks to indented code blocks (kramdown native format)
        # ```lang\ncode\n``` → indented with 4 spaces
        result.gsub!(/^```\w*\n(.*?)^```/m) do
          code = $1
          code.lines.map { |line| "    #{line}" }.join
        end

        # Convert ~~strikethrough~~ to HTML <del> tags (kramdown will pass through)
        result.gsub!(/~~([^~]+)~~/, '<del>\1</del>')

        result
      end

      # Convert HTML to WhatsApp formatting syntax
      def html_to_whatsapp(html)
        result = html.dup

        # Convert code blocks first (before inline code)
        # <pre><code>...</code></pre> → ```...```
        result.gsub!(%r{<pre[^>]*><code[^>]*>(.*?)</code></pre>}m) { "```#{$1}```" }

        # Convert inline code: <code>...</code> → `...`
        result.gsub!(%r{<code[^>]*>(.*?)</code>}m) { "`#{$1}`" }

        # Convert bold: <strong>...</strong> or <b>...</b> → *...*
        result.gsub!(%r{<(?:strong|b)[^>]*>(.*?)</(?:strong|b)>}m) { "*#{$1}*" }

        # Convert italic: <em>...</em> or <i>...</i> → _..._
        result.gsub!(%r{<(?:em|i)[^>]*>(.*?)</(?:em|i)>}m) { "_#{$1}_" }

        # Convert strikethrough: <s>...</s>, <del>...</del>, <strike>...</strike> → ~...~
        result.gsub!(%r{<(?:s|del|strike)[^>]*>(.*?)</(?:s|del|strike)>}m) { "~#{$1}~" }

        # Convert paragraphs to double newlines
        result.gsub!(%r{<p[^>]*>(.*?)</p>}m) { "#{$1}\n\n" }

        # Convert line breaks
        result.gsub!(/<br\s*\/?>/, "\n")

        # Convert links: <a href="url">text</a> → text (url)
        # WhatsApp auto-links URLs, so we just show text and URL
        result.gsub!(%r{<a[^>]*href=["']([^"']+)["'][^>]*>(.*?)</a>}m) do
          url, text = $1, $2
          (text == url) ? url : "#{text} (#{url})"
        end

        # Convert blockquotes (WhatsApp doesn't have native support, use > prefix)
        result.gsub!(%r{<blockquote[^>]*>(.*?)</blockquote>}m) do
          $1.lines.map { |line| "> #{line.strip}" }.join("\n")
        end

        # Convert lists
        result.gsub!(%r{<ul[^>]*>(.*?)</ul>}m) do
          items = $1.scan(%r{<li[^>]*>(.*?)</li>}m).flatten
          items.map { |item| "• #{item.strip}" }.join("\n")
        end
        result.gsub!(%r{<ol[^>]*>(.*?)</ol>}m) do
          items = $1.scan(%r{<li[^>]*>(.*?)</li>}m).flatten
          items.map.with_index(1) { |item, i| "#{i}. #{item.strip}" }.join("\n")
        end

        # Strip any remaining HTML tags
        result.gsub!(/<[^>]+>/, "")

        # Decode HTML entities
        result.gsub!("&amp;", "&")
        result.gsub!("&lt;", "<")
        result.gsub!("&gt;", ">")
        result.gsub!("&quot;", '"')
        result.gsub!("&#39;", "'")
        result.gsub!("&nbsp;", " ")

        # Clean up excessive newlines
        result.gsub!(/\n{3,}/, "\n\n")

        result.strip
      end
    end
  end
end

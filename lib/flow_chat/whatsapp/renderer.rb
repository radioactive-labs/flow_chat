require "flow_chat/renderers/markdown_support"

module FlowChat
  module Whatsapp
    class Renderer
      include FlowChat::Renderers::MarkdownSupport

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

      def build_media_message
        media_type = media[:type] || :image
        url = media[:url]
        id = media[:id]
        filename = media[:filename]

        case media_type.to_sym
        when :image
          options = {}
          options[:url] = url if url
          options[:id] = id if id
          options[:caption] = formatted_caption if formatted_caption
          [:media_image, "", options]
        when :document
          options = {}
          options[:url] = url if url
          options[:id] = id if id
          options[:caption] = formatted_caption if formatted_caption
          options[:filename] = filename if filename
          [:media_document, "", options]
        when :audio
          options = {}
          options[:url] = url if url
          options[:id] = id if id
          options[:caption] = formatted_caption if formatted_caption
          [:media_audio, "", options]
        when :video
          options = {}
          options[:url] = url if url
          options[:id] = id if id
          options[:caption] = formatted_caption if formatted_caption
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

      def build_selection_message_with_media
        # Convert array to hash with index-based keys if needed, same as build_selection_message
        if choices.is_a?(Array)
          choice_hash = choices.each_with_index.to_h { |choice, index| [index.to_s, choice] }
          build_buttons_message_with_media(choice_hash)
        elsif choices.is_a?(Hash)
          build_buttons_message_with_media(choices)
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

        [:interactive_buttons, formatted_message, {buttons: buttons}]
      end

      def build_buttons_message_with_media(choices)
        buttons = choices.map do |key, value|
          {
            id: key.to_s,
            title: truncate_text(value.to_s, 20) # WhatsApp button titles have a 20 character limit
          }
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

        [:interactive_list, formatted_message, {sections: sections}]
      end

      def truncate_text(text, length)
        return text if text.length <= length
        text[0, length - 3] + "..."
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

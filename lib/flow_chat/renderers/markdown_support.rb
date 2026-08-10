require "kramdown"
require "rails-html-sanitizer"

module FlowChat
  module Renderers
    module MarkdownSupport
      def to_html(text)
        return "" if text.nil?

        html = Kramdown::Document.new(text.to_s, **kramdown_options).to_html.strip
        sanitize_html(html)
      end

      def sanitize_html(html)
        sanitized = self.class.sanitizer.sanitize(
          html,
          tags: allowed_tags,
          attributes: allowed_attributes
        )

        post_process_html(sanitized)
      end

      # Markdown rendered as plain text, for platforms with no rich text at all.
      # Messenger and Instagram both fall here: they display exactly the
      # characters sent, so any leftover markup is noise the user reads.
      def to_plain_text(text)
        return "" if text.nil?

        html = Kramdown::Document.new(text.to_s, **kramdown_options).to_html.strip
        html_to_plain_text(html)
      end

      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        def sanitizer
          @sanitizer ||= Rails::Html::SafeListSanitizer.new
        end
      end

      private

      # Override in subclasses to customize Kramdown options
      # Default uses straight quotes (ASCII 39/34) instead of curly smart quotes
      def kramdown_options
        {smart_quotes: [39, 39, 34, 34]}
      end

      # Override in subclasses to specify allowed HTML tags
      def allowed_tags
        %w[b strong i em a code pre]
      end

      # Override in subclasses to specify allowed HTML attributes
      def allowed_attributes
        %w[href]
      end

      # Override in subclasses to post-process sanitized HTML
      def post_process_html(html)
        html
      end

      def html_to_plain_text(html)
        result = html.dup

        # Code blocks and inline code keep their content, lose their markers.
        result.gsub!(%r{<pre[^>]*><code[^>]*>(.*?)</code></pre>}m) { $1.strip }
        result.gsub!(%r{<code[^>]*>(.*?)</code>}m) { $1 }

        # Links first: the anchor text is needed before tags are stripped.
        result.gsub!(%r{<a[^>]*href=["']([^"']+)["'][^>]*>(.*?)</a>}m) do
          url, text = $1, $2
          (text == url) ? url : "#{text} (#{url})"
        end

        result.gsub!(%r{<ul[^>]*>(.*?)</ul>}m) do
          $1.scan(%r{<li[^>]*>(.*?)</li>}m).flatten.map { |item| "• #{item.strip}" }.join("\n")
        end
        result.gsub!(%r{<ol[^>]*>(.*?)</ol>}m) do
          $1.scan(%r{<li[^>]*>(.*?)</li>}m).flatten.map.with_index(1) { |item, i| "#{i}. #{item.strip}" }.join("\n")
        end

        result.gsub!(%r{<blockquote[^>]*>(.*?)</blockquote>}m) do
          $1.lines.map { |line| "> #{line.strip}" }.join("\n")
        end

        result.gsub!(%r{<p[^>]*>(.*?)</p>}m) { "#{$1}\n\n" }
        result.gsub!(/<br\s*\/?>/, "\n")

        # Every remaining tag, emphasis included, goes without replacement.
        result.gsub!(/<[^>]+>/, "")

        result.gsub!("&amp;", "&")
        result.gsub!("&lt;", "<")
        result.gsub!("&gt;", ">")
        result.gsub!("&quot;", '"')
        result.gsub!("&#39;", "'")
        result.gsub!("&nbsp;", " ")

        result.gsub!(/\n{3,}/, "\n\n")

        result.strip
      end
    end
  end
end

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

      # A list whose items hold no further list, which is the only kind that
      # can be turned into text without looking inside itself first.
      INNERMOST_UNORDERED = %r{<ul[^>]*>((?:(?!<[uo]l\b).)*?)</ul>}m
      INNERMOST_ORDERED = %r{<ol[^>]*>((?:(?!<[uo]l\b).)*?)</ol>}m

      # Renders lists from the inside out.
      #
      # A single non-greedy pass over <ul>(.*?)</ul> pairs an outer opening tag
      # with the *inner* list's closing tag, so on a nested list only the first
      # item kept its bullet and the leftover </li></ul> was later stripped as
      # a bare tag - leaving stray indented lines, and on some inputs raw
      # markup, in a message a user reads.
      #
      # Innermost lists are replaced first and the loop repeats, so by the time
      # an outer list is matched its children are already plain text and it
      # contains no list markup to mispair with. Continuation lines are
      # indented, which is what makes the nesting legible once the tags are
      # gone.
      def replace_lists(html)
        # The markdown's own indentation survives into the HTML as whitespace
        # around the list tags. Removed once, up front, so that from here on the
        # only indentation in play is the kind this method adds - otherwise the
        # two compound and each level steps further right than the last.
        result = html.gsub(%r{\s*(</?(?:ul|ol|li)\b[^>]*>)\s*}m) { $1 }

        loop do
          changed = false

          # Each rendered list opens on its own line. Without it, a nested list
          # would run straight on from the text of the item holding it, and the
          # parent pass would see one line where there are two.
          result = result.gsub(INNERMOST_UNORDERED) do
            changed = true
            "\n" + list_items($1) { |item, _index| "• #{item}" }
          end

          result = result.gsub(INNERMOST_ORDERED) do
            changed = true
            "\n" + list_items($1) { |item, index| "#{index}. #{item}" }
          end

          break unless changed
        end

        result
      end

      def list_items(html)
        html.scan(%r{<li[^>]*>(.*?)</li>}m).flatten.map.with_index(1) do |item, index|
          # Continuation lines are left exactly as they are: they were produced
          # by an earlier pass over a nested list and already carry that level's
          # indentation, which stripping would flatten. Source whitespace is
          # gone by now - replace_lists removes it around the list tags before
          # any of this runs.
          lines = item.strip.split("\n").reject { |line| line.strip.empty? }
          marked = yield(lines.shift.to_s.strip, index)

          # Anything after the first line is an already-rendered nested list.
          [marked, *lines.map { |line| "  #{line}" }].join("\n")
        end.join("\n")
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

        result = replace_lists(result)

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

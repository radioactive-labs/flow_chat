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
    end
  end
end

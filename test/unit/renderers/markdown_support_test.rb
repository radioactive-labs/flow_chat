require "test_helper"
require "flow_chat/renderers/markdown_support"

class FlowChat::Renderers::MarkdownSupportTest < Minitest::Test
  class TestRenderer
    include FlowChat::Renderers::MarkdownSupport
  end

  def setup
    @renderer = TestRenderer.new
  end

  # Basic conversion tests

  def test_to_html_converts_markdown_to_html
    result = @renderer.to_html("Hello **bold** world")
    assert_includes result, "<strong>bold</strong>"
  end

  def test_to_html_returns_empty_string_for_nil
    result = @renderer.to_html(nil)
    assert_equal "", result
  end

  def test_to_html_converts_non_string_to_string
    result = @renderer.to_html(123)
    assert_includes result, "123"
  end

  def test_to_html_strips_whitespace
    result = @renderer.to_html("  hello  ")
    # Kramdown wraps in <p> tags, result should be stripped
    refute_match(/^\s/, result)
    refute_match(/\s$/, result)
  end

  # Default kramdown options tests

  def test_default_kramdown_options_uses_straight_quotes
    result = @renderer.to_html("He said 'hello' and \"goodbye\"")

    # Should have straight quotes, not curly
    assert_includes result, "'"
    assert_includes result, '"'
    refute_includes result, "\u2018"  # left single curly quote
    refute_includes result, "\u2019"  # right single curly quote
    refute_includes result, "\u201C"  # left double curly quote
    refute_includes result, "\u201D"  # right double curly quote
  end

  # Default allowed tags tests

  def test_default_allowed_tags
    result = @renderer.to_html("<b>bold</b> <strong>strong</strong> <i>italic</i> <em>em</em>")

    assert_includes result, "<b>bold</b>"
    assert_includes result, "<strong>strong</strong>"
    assert_includes result, "<i>italic</i>"
    assert_includes result, "<em>em</em>"
  end

  def test_default_allows_inline_code
    result = @renderer.to_html("Use `code` here")

    assert_includes result, "<code>code</code>"
  end

  def test_default_allows_code_blocks
    # Kramdown uses indented blocks (4 spaces) for pre/code
    result = @renderer.to_html("    def hello\n      puts 'hi'\n    end")

    assert_includes result, "<pre>"
    assert_includes result, "<code>"
  end

  def test_default_allows_links_with_href
    result = @renderer.to_html('<a href="https://example.com">link</a>')

    assert_includes result, '<a href="https://example.com">link</a>'
  end

  def test_default_strips_disallowed_tags
    result = @renderer.to_html("<script>alert('xss')</script>")

    refute_includes result, "<script>"
    refute_includes result, "</script>"
  end

  def test_default_strips_p_tags
    # Default allowed_tags doesn't include <p>
    result = @renderer.to_html("Hello world")

    # Kramdown generates <p> but sanitizer strips it by default
    refute_includes result, "<p>"
  end

  # Attribute filtering tests

  def test_default_strips_disallowed_attributes
    result = @renderer.to_html('<a href="https://example.com" onclick="alert()">link</a>')

    assert_includes result, 'href="https://example.com"'
    refute_includes result, "onclick"
  end

  # Sanitizer caching tests

  def test_sanitizer_is_cached_per_class
    sanitizer1 = TestRenderer.sanitizer
    sanitizer2 = TestRenderer.sanitizer

    assert_same sanitizer1, sanitizer2
  end

  # Override behavior tests

  class CustomRenderer
    include FlowChat::Renderers::MarkdownSupport

    def kramdown_options
      {auto_ids: false}
    end

    def allowed_tags
      %w[p div span]
    end

    def allowed_attributes
      %w[class id]
    end

    def post_process_html(html)
      html.upcase
    end
  end

  def test_kramdown_options_can_be_overridden
    renderer = CustomRenderer.new
    result = renderer.to_html("# Heading")

    # With auto_ids: false, heading shouldn't have id attribute
    refute_includes result, "id="
  end

  def test_allowed_tags_can_be_overridden
    renderer = CustomRenderer.new
    result = renderer.to_html("<div>content</div> <script>bad</script>")

    assert_includes result, "DIV"  # post_process uppercases
    refute_includes result, "SCRIPT"
  end

  def test_allowed_attributes_can_be_overridden
    renderer = CustomRenderer.new
    result = renderer.to_html('<div class="foo" onclick="bad">content</div>')

    assert_includes result, "CLASS"  # post_process uppercases
    refute_includes result, "ONCLICK"
  end

  def test_post_process_html_can_be_overridden
    renderer = CustomRenderer.new
    result = renderer.to_html("hello")

    assert_equal result, result.upcase
  end
end

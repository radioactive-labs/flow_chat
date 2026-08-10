require "test_helper"

class PlainTextSupportTest < Minitest::Test
  class Subject
    include FlowChat::Renderers::MarkdownSupport

    public :to_plain_text
  end

  def setup
    @subject = Subject.new
  end

  def test_strips_emphasis
    assert_equal "bold and italic", @subject.to_plain_text("**bold** and _italic_")
  end

  def test_unordered_list_becomes_bullets
    assert_equal "• one\n• two", @subject.to_plain_text("- one\n- two")
  end

  def test_ordered_list_is_numbered
    assert_equal "1. one\n2. two", @subject.to_plain_text("1. one\n2. two")
  end

  def test_link_shows_text_and_url
    assert_equal "Docs (https://example.com)", @subject.to_plain_text("[Docs](https://example.com)")
  end

  def test_link_with_url_as_text_shows_url_once
    assert_equal "https://example.com", @subject.to_plain_text("[https://example.com](https://example.com)")
  end

  def test_decodes_entities
    assert_equal "Tom & Jerry", @subject.to_plain_text("Tom &amp; Jerry")
  end

  def test_nil_is_empty_string
    assert_equal "", @subject.to_plain_text(nil)
  end
end

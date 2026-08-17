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

  # A single non-greedy pass over <ul>(.*?)</ul> paired the outer opening tag
  # with the inner list's closing tag, so only the first item kept its bullet
  # and the leftover </li></ul> was stripped later as a bare tag - leaving
  # stray indented lines in a message a user reads. Messenger and Instagram
  # send every prompt through here, so it shipped.
  def test_nested_unordered_list_keeps_every_bullet
    assert_equal "• a\n  • b\n• c", @subject.to_plain_text("- a\n  - b\n- c")
  end

  def test_nested_ordered_list_keeps_every_number
    assert_equal "1. one\n  1. sub\n2. two", @subject.to_plain_text("1. one\n   1. sub\n2. two")
  end

  def test_a_list_nested_three_deep_indents_each_level
    assert_equal "• a\n  • b\n    • c\n• d", @subject.to_plain_text("- a\n  - b\n    - c\n- d")
  end

  def test_an_ordered_list_nested_in_an_unordered_one_keeps_both_markers
    assert_equal "• top\n  1. first\n  2. second\n• other",
      @subject.to_plain_text("- top\n  1. first\n  2. second\n- other")
  end

  def test_no_markup_survives_a_nested_list
    result = @subject.to_plain_text("Pick one:\n\n- a\n  - b\n- c\n")

    refute_includes result, "<"
    refute_includes result, ">"
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

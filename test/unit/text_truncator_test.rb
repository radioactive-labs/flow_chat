require "test_helper"

module FlowChat
  class TextTruncatorTest < Minitest::Test
    def test_returns_text_unchanged_when_within_the_limit
      assert_equal "Alpha", TextTruncator.truncate("Alpha", 20)
    end

    def test_returns_text_unchanged_when_exactly_at_the_limit
      text = "a" * 20
      assert_equal text, TextTruncator.truncate(text, 20)
    end

    def test_truncates_and_appends_an_ellipsis_over_the_limit
      text = "A label that is definitely longer than twenty chars"
      result = TextTruncator.truncate(text, 20)

      assert_equal 20, result.length
      assert_equal "A label that is d...", result
    end
  end
end

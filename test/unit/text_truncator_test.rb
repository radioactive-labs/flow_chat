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

    def test_number_prefixes_a_short_label_unchanged
      assert_equal "1. Alpha", TextTruncator.number("Alpha", 1, 20)
    end

    def test_number_grows_the_prefix_with_position
      assert_equal "10. Alpha", TextTruncator.number("Alpha", 10, 20)
      assert_equal "100. Alpha", TextTruncator.number("Alpha", 100, 20)
    end

    def test_number_truncates_the_label_to_leave_room_for_its_own_prefix
      text = "A label that is definitely longer than twenty chars"

      result = TextTruncator.number(text, 1, 20)

      assert_equal 20, result.length
      assert_equal "1. A label that i...", result
    end

    # Position 10's prefix ("10. ") is one character longer than position
    # 1's ("1. "), so it must eat one more character from the label to stay
    # within the same cap - this is why the prefix has to be computed per
    # choice rather than once for the whole rung.
    def test_number_truncates_more_for_a_longer_prefix
      text = "A label that is definitely longer than twenty chars"

      result = TextTruncator.number(text, 10, 20)

      assert_equal 20, result.length
      assert_equal "10. A label that ...", result
    end
  end
end

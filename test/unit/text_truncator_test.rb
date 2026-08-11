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

    # Below 3 there is no room for the ellipsis (it alone is 3 characters),
    # so truncate falls back to a hard cut with no ellipsis rather than
    # returning text longer than the cap - or, before this was clamped,
    # crashing: text[0, length - 3] is text[0, negative], which is nil, and
    # nil + "..." raised NoMethodError.
    def test_truncates_with_no_ellipsis_when_the_cap_is_too_small_for_one
      text = "Alpha"

      assert_equal "A", TextTruncator.truncate(text, 1)
      assert_equal "Al", TextTruncator.truncate(text, 2)
    end

    def test_a_cap_of_zero_returns_an_empty_string
      assert_equal "", TextTruncator.truncate("Alpha", 0)
    end

    # Not reachable through any current renderer's own cap, but #number
    # below can pass a negative width once its prefix alone is longer than
    # the cap, so this is exercised directly rather than only through it.
    def test_a_negative_cap_does_not_raise
      assert_equal "", TextTruncator.truncate("Alpha", -5)
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

    # position 100's prefix ("100. ") is already 5 characters, so at a cap
    # this small the label's own width passed to #truncate goes negative.
    # Not reachable through any of today's caps, but a shared public entry
    # point should not turn a future, smaller limits object into a 500.
    def test_number_does_not_raise_when_the_prefix_alone_exceeds_the_cap
      result = TextTruncator.number("Alpha", 100, 3)

      refute_nil result
    end
  end
end

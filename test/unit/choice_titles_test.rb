require "test_helper"

module FlowChat
  class ChoiceTitlesTest < Minitest::Test
    def test_short_distinct_labels_are_not_prefixed
      choices = {"a" => "Alpha", "b" => "Beta"}

      titles = ChoiceTitles.build(choices, 20)

      assert_equal [
        ["a", "Alpha", "Alpha", false],
        ["b", "Beta", "Beta", false]
      ], titles
    end

    def test_ambiguous_is_false_for_short_distinct_labels
      refute ChoiceTitles.ambiguous?({"a" => "Alpha", "b" => "Beta"}, 20)
    end

    def test_a_label_that_needs_truncation_prefixes_the_whole_set
      long_label = "A label that is definitely longer than twenty chars"
      choices = {"a" => long_label, "b" => "Beta"}

      titles = ChoiceTitles.build(choices, 20)

      assert_equal "1. A label that i...", titles[0][2]
      assert_equal "2. Beta", titles[1][2]
      assert ChoiceTitles.ambiguous?(choices, 20)
    end

    # This is a1d08a4's original bug: two different labels truncate to the
    # same displayed text at a 20-char cap.
    def test_truncation_collision_prefixes_the_whole_set
      choices = {
        "savings" => "Transfer to savings account",
        "salary" => "Transfer to salary account"
      }

      titles = ChoiceTitles.build(choices, 20)

      assert_equal "1. Transfer to sa...", titles[0][2]
      assert_equal "2. Transfer to sa...", titles[1][2]
    end

    # No truncation is involved at all here - both labels fit the cap
    # untouched - but two choices sharing a label is exactly as ambiguous as
    # a truncation collision: the displayed text still can't tell them
    # apart without a prefix.
    def test_duplicate_labels_prefix_the_whole_set_even_without_truncation
      choices = {"yes" => "Accept", "no" => "Accept"}

      titles = ChoiceTitles.build(choices, 20)

      assert_equal "1. Accept", titles[0][2]
      assert_equal "2. Accept", titles[1][2]
      assert ChoiceTitles.ambiguous?(choices, 20)
    end

    def test_truncated_flag_accounts_for_the_prefix_eating_into_the_cap
      long_label = "A label that is definitely longer than twenty chars"
      choices = {"a" => long_label, "b" => "Beta"}

      titles = ChoiceTitles.build(choices, 20)

      _, _, _, a_truncated = titles[0]
      _, _, _, b_truncated = titles[1]

      assert a_truncated, "the long label must be marked truncated"
      refute b_truncated, "\"Beta\" fits even after losing room to its \"2. \" prefix"
    end

    def test_truncated_flag_is_false_for_untouched_labels_when_not_ambiguous
      choices = {"a" => "Alpha", "b" => "Beta"}

      titles = ChoiceTitles.build(choices, 20)

      assert titles.all? { |_key, _label, _title, truncated| !truncated }
    end

    def test_no_prefixed_title_exceeds_the_cap
      choices = (1..12).to_h { |i| ["k#{i}", "A moderately long option label number #{i}"] }

      titles = ChoiceTitles.build(choices, 20)

      titles.each do |_key, _label, title, _truncated|
        assert_operator title.length, :<=, 20
      end
    end

    def test_ambiguity_reason_names_duplicates
      choices = {"yes" => "Accept", "no" => "Accept"}

      reason = ChoiceTitles.ambiguity_reason(choices, 20)

      assert_includes reason, "duplicate titles"
      assert_includes reason, "Accept"
    end

    def test_ambiguity_reason_names_truncated_labels
      long_label = "A label that is definitely longer than twenty chars"
      choices = {"a" => long_label, "b" => "Beta"}

      reason = ChoiceTitles.ambiguity_reason(choices, 20)

      assert_includes reason, "truncated"
      assert_includes reason, long_label
    end

    def test_ambiguity_reason_is_nil_when_not_ambiguous
      assert_nil ChoiceTitles.ambiguity_reason({"a" => "Alpha", "b" => "Beta"}, 20)
    end
  end
end

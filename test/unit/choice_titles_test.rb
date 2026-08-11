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

    # --- aliases_for ---------------------------------------------------
    #
    # Folded in from the former ChoiceAliasBuilder: its whole body delegated
    # to this module, and its correctness rested entirely on the guarantee
    # .build makes above (never two identical titles for the same set), so
    # it was one concept split across two top-level constants.

    def test_aliases_for_no_display_cap_means_no_aliases
      choices = {"a" => "Alpha"}
      generated_ids = {"a" => "Alpha"}

      assert_equal({}, ChoiceTitles.aliases_for(choices, generated_ids, nil))
    end

    # "Alpha" is short and unique, so .build does not prefix it; its bare
    # title is then identical to its own generated id, which is exactly the
    # case aliases_for skips as pointless - the id map already resolves it.
    def test_aliases_for_short_unique_label_is_not_aliased_because_its_title_equals_its_own_id
      choices = {"a" => "Alpha"}
      generated_ids = {"a" => "Alpha"}

      assert_equal({}, ChoiceTitles.aliases_for(choices, generated_ids, 20))
    end

    def test_aliases_for_long_label_is_aliased_to_its_numbered_truncated_title
      long_label = "A label that is definitely longer than twenty chars"
      choices = {"a" => long_label}
      generated_ids = {"a" => long_label}

      aliases = ChoiceTitles.aliases_for(choices, generated_ids, 20)

      assert_equal({"1. A label that i..." => "a"}, aliases)
    end

    def test_aliases_for_position_is_read_from_enumeration_order_not_from_the_choice_key
      long_label = "A label that is definitely longer than twenty chars"
      choices = {"z" => long_label, "a" => "Beta"}
      generated_ids = {"z" => long_label, "a" => "Beta"}

      aliases = ChoiceTitles.aliases_for(choices, generated_ids, 20)

      assert_equal({"1. A label that i..." => "z", "2. Beta" => "a"}, aliases)
    end

    # This is the case a1d08a4 could not alias for either choice: both
    # labels truncate to the same "Transfer to sa..." at a 20-char cap, so
    # the old collision-dropping builder registered neither. .build now
    # prefixes the whole set, making the two titles distinct by
    # construction, so both are aliased.
    def test_aliases_for_labels_that_would_collide_without_a_prefix_both_resolve
      choices = {
        "savings" => "Transfer to savings account",
        "salary" => "Transfer to salary account"
      }
      generated_ids = {"savings" => choices["savings"], "salary" => choices["salary"]}

      aliases = ChoiceTitles.aliases_for(choices, generated_ids, 20)

      assert_equal(
        {"1. Transfer to sa..." => "savings", "2. Transfer to sa..." => "salary"},
        aliases
      )
    end

    # Two choices sharing a label outright, with no truncation involved:
    # .build prefixes the set for this too, so each alias still identifies
    # exactly one choice.
    def test_aliases_for_duplicate_labels_are_both_aliased_to_their_own_distinct_key
      choices = {"yes" => "Accept", "no" => "Accept"}
      generated_ids = {"yes" => "Accept", "no" => "Accept a1b"}

      aliases = ChoiceTitles.aliases_for(choices, generated_ids, 20)

      assert_equal({"1. Accept" => "yes", "2. Accept" => "no"}, aliases)
    end
  end
end

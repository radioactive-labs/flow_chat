require "test_helper"

module FlowChat
  class ChoiceAliasBuilderTest < Minitest::Test
    def test_no_display_cap_means_no_aliases
      choices = {"a" => "Alpha"}
      generated_ids = {"a" => "Alpha"}

      assert_equal({}, ChoiceAliasBuilder.build(choices, generated_ids, nil))
    end

    # "Alpha" is short and unique, so FlowChat::ChoiceTitles does not prefix
    # it; its bare title is then identical to its own generated id, which is
    # exactly the case ChoiceAliasBuilder skips as pointless - the id map
    # already resolves it.
    def test_short_unique_label_is_not_aliased_because_its_title_equals_its_own_id
      choices = {"a" => "Alpha"}
      generated_ids = {"a" => "Alpha"}

      assert_equal({}, ChoiceAliasBuilder.build(choices, generated_ids, 20))
    end

    def test_long_label_is_aliased_to_its_numbered_truncated_title
      long_label = "A label that is definitely longer than twenty chars"
      choices = {"a" => long_label}
      generated_ids = {"a" => long_label}

      aliases = ChoiceAliasBuilder.build(choices, generated_ids, 20)

      assert_equal({"1. A label that i..." => "a"}, aliases)
    end

    def test_position_is_read_from_enumeration_order_not_from_the_choice_key
      long_label = "A label that is definitely longer than twenty chars"
      choices = {"z" => long_label, "a" => "Beta"}
      generated_ids = {"z" => long_label, "a" => "Beta"}

      aliases = ChoiceAliasBuilder.build(choices, generated_ids, 20)

      assert_equal({"1. A label that i..." => "z", "2. Beta" => "a"}, aliases)
    end

    # This is the case a1d08a4 could not alias for either choice: both
    # labels truncate to the same "Transfer to sa..." at a 20-char cap, so
    # the old collision-dropping builder registered neither. FlowChat::
    # ChoiceTitles now prefixes the whole set, making the two titles
    # distinct by construction, so both are aliased.
    def test_labels_that_would_collide_without_a_prefix_both_resolve
      choices = {
        "savings" => "Transfer to savings account",
        "salary" => "Transfer to salary account"
      }
      generated_ids = {"savings" => choices["savings"], "salary" => choices["salary"]}

      aliases = ChoiceAliasBuilder.build(choices, generated_ids, 20)

      assert_equal(
        {"1. Transfer to sa..." => "savings", "2. Transfer to sa..." => "salary"},
        aliases
      )
    end

    # Two choices sharing a label outright, with no truncation involved:
    # FlowChat::ChoiceTitles prefixes the set for this too, so each alias
    # still identifies exactly one choice.
    def test_duplicate_labels_are_both_aliased_to_their_own_distinct_key
      choices = {"yes" => "Accept", "no" => "Accept"}
      generated_ids = {"yes" => "Accept", "no" => "Accept a1b"}

      aliases = ChoiceAliasBuilder.build(choices, generated_ids, 20)

      assert_equal({"1. Accept" => "yes", "2. Accept" => "no"}, aliases)
    end
  end
end

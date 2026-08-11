require "test_helper"

module FlowChat
  class ChoiceAliasBuilderTest < Minitest::Test
    def test_no_display_cap_means_no_aliases
      choices = {"a" => "Alpha"}
      generated_ids = {"a" => "Alpha"}

      assert_equal({}, ChoiceAliasBuilder.build(choices, generated_ids, nil))
    end

    def test_short_label_is_not_aliased_because_it_already_equals_its_id
      choices = {"a" => "Alpha"}
      generated_ids = {"a" => "Alpha"}

      assert_equal({}, ChoiceAliasBuilder.build(choices, generated_ids, 20))
    end

    def test_truncated_label_is_aliased_to_its_choice_key
      long_label = "A label that is definitely longer than twenty chars"
      choices = {"a" => long_label}
      generated_ids = {"a" => long_label}

      aliases = ChoiceAliasBuilder.build(choices, generated_ids, 20)

      assert_equal({"A label that is d..." => "a"}, aliases)
    end

    # Two different labels truncating to the same displayed string must not
    # alias either: a truncated reply could be typed by a user looking at
    # either choice, and there is no way to tell which one they meant.
    def test_colliding_truncated_labels_alias_neither
      choices = {
        "a" => "A label that is definitely one thing",
        "b" => "A label that is definitely another"
      }
      generated_ids = {
        "a" => choices["a"],
        "b" => choices["b"]
      }

      aliases = ChoiceAliasBuilder.build(choices, generated_ids, 20)

      assert_empty aliases
    end

    # A truncated label must not steal a string another choice already owns
    # as its generated id, even though it is a singleton among the truncated
    # candidates: typing that string is ambiguous between "the id" and "the
    # alias". This mirrors the real duplicate-label case documented on the
    # WhatsApp mapper: two choices labelled "Accept" get ids "Accept" and
    # "Accept <hash>", but both still display "Accept" once rendered.
    def test_truncated_label_colliding_with_another_choices_id_is_not_aliased
      choices = {
        "special" => "Accept",
        "other" => "Accept"
      }
      generated_ids = {
        "special" => "Accept",
        "other" => "Accept a1b"
      }

      aliases = ChoiceAliasBuilder.build(choices, generated_ids, 20)

      assert_empty aliases
    end
  end
end

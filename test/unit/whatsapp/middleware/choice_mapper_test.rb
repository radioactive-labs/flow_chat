require "test_helper"

module FlowChat
  module Whatsapp
    module Middleware
      class ChoiceMapperTest < Minitest::Test
        def setup
          @app = Minitest::Mock.new
          @middleware = ChoiceMapper.new(@app)
          @session = MockSession.new
          @context = MockContext.new(@session)
        end

        def test_no_interception_without_mapping
          @context.input = "some_input"
          @app.expect :call, [:text, "response", nil, nil], [@context]

          result = @middleware.call(@context)

          assert_equal "some_input", @context.input
          assert_equal [:text, "response", nil, nil], result
          @app.verify
        end

        def test_no_interception_with_blank_input
          @session.set("whatsapp.choice_mapping", {"accept" => "original_accept"})
          @context.input = nil
          @app.expect :call, [:text, "response", nil, nil], [@context]

          @middleware.call(@context)

          assert_nil @context.input
          @app.verify
        end

        def test_intercepts_and_maps_choice
          mapping = {"create_account" => "create", "login" => "login"}
          @session.set("whatsapp.choice_mapping", mapping)
          @context.input = "create_account"
          @app.expect :call, [:text, "response", nil, nil], [@context]

          @middleware.call(@context)

          assert_equal "create", @context.input
          @app.verify
        end

        def test_intercepts_duplicate_with_hash
          mapping = {
            "accept" => "accept_option_1",
            "accept_a1b2c3" => "accept_option_2"
          }
          @session.set("whatsapp.choice_mapping", mapping)
          @context.input = "accept_a1b2c3"
          @app.expect :call, [:text, "response", nil, nil], [@context]

          @middleware.call(@context)

          assert_equal "accept_option_2", @context.input
          @app.verify
        end

        def test_passes_through_unmapped_input
          mapping = {"accept" => "original_accept"}
          @session.set("whatsapp.choice_mapping", mapping)
          @context.input = "free_text_response"
          @app.expect :call, [:text, "response", nil, nil], [@context]

          @middleware.call(@context)

          assert_equal "free_text_response", @context.input
          @app.verify
        end

        def test_creates_mapping_from_choices
          # Middleware receives choices from app and creates mapping
          choices = {"create" => "Create Account", "login" => "Login"}
          @app.expect :call, [:text, "response", choices, nil], [@context]

          _, _, transformed_choices, _ = @middleware.call(@context)

          # Middleware should transform choices to use generated IDs as keys
          assert_equal "Create Account", transformed_choices["Create Account"]
          assert_equal "Login", transformed_choices["Login"]

          # Middleware should store mapping: generated_id => original_key
          mapping = @session.get("whatsapp.choice_mapping")
          assert_equal "create", mapping["Create Account"]
          assert_equal "login", mapping["Login"]
          @app.verify
        end

        def test_clears_mapping_on_blank_input
          mapping = {"accept" => "original_accept"}
          @session.set("whatsapp.choice_mapping", mapping)
          @context.input = nil
          @app.expect :call, [:text, "response", nil, nil], [@context]

          @middleware.call(@context)

          assert_nil @session.get("whatsapp.choice_mapping")
          @app.verify
        end

        def test_clears_mapping_when_input_doesnt_match
          mapping = {"accept" => "original_accept"}
          @session.set("whatsapp.choice_mapping", mapping)
          @context.input = "unrelated_input"
          @app.expect :call, [:text, "response", nil, nil], [@context]

          @middleware.call(@context)

          # Mapping should be cleared before app.call
          assert_nil @session.get("whatsapp.choice_mapping")
          @app.verify
        end

        def test_clears_mapping_after_successful_match
          mapping = {"accept" => "original_accept", "decline" => "original_decline"}
          @session.set("whatsapp.choice_mapping", mapping)
          @context.input = "accept"
          @app.expect :call, [:text, "response", nil, nil], [@context]

          @middleware.call(@context)

          # Input should be mapped
          assert_equal "original_accept", @context.input

          # Mapping should be cleared after successful match (like USSD does)
          assert_nil @session.get("whatsapp.choice_mapping")
          @app.verify
        end

        def test_replaces_old_mapping_with_new
          # Old mapping exists in session
          old_mapping = {"old_button" => "old_choice"}
          @session.set("whatsapp.choice_mapping", old_mapping)

          # App returns new choices
          new_choices = {"new_option" => "New Choice"}
          @app.expect :call, [:text, "response", new_choices, nil], [@context]

          @middleware.call(@context)

          # New mapping should replace old
          mapping = @session.get("whatsapp.choice_mapping")
          assert_equal "new_option", mapping["New Choice"]
          @app.verify
        end

        def test_multiple_sequential_mappings
          # First interaction - app returns choices
          choices1 = {"choice1" => "Button 1"}
          @app.expect :call, [:text, "response1", choices1, nil], [@context]
          @middleware.call(@context)

          # Verify mapping was stored
          mapping = @session.get("whatsapp.choice_mapping")
          assert_equal "choice1", mapping["Button 1"]

          # Second interaction - user responds with generated ID
          @context.input = "Button 1"
          @app.expect :call, [:text, "response2", nil, nil], [@context]
          @middleware.call(@context)

          # Input should be mapped back to original key
          assert_equal "choice1", @context.input
          @app.verify
        end

        def test_empty_mapping_hash_is_treated_as_no_mapping
          @session.set("whatsapp.choice_mapping", {})
          @context.input = "some_input"
          @app.expect :call, [:text, "response", nil, nil], [@context]

          @middleware.call(@context)

          assert_equal "some_input", @context.input
          @app.verify
        end

        def test_typed_number_resolves_on_the_numbered_rung
          choices = (1..25).to_h { |i| ["key#{i}", "Option #{i}"] }
          @app.expect :call, [:text, "response", choices, nil], [@context]

          @middleware.call(@context)

          @context.input = "3"
          @app.expect :call, [:text, "response", nil, nil], [@context]

          @middleware.call(@context)

          assert_equal "key3", @context.input
          @app.verify
        end

        # A generated id and a stored position occupy the same key space:
        # IdGenerator#normalize_label keeps \w, which includes digits, so a
        # choice labelled "5" generates the id "5", the same string as the
        # position of the 5th choice. Ids must win: get_choice_mapping is
        # consulted before get_position_mapping.
        def test_generated_ids_win_over_positions
          choices = {"k1" => "5"}.merge((2..11).to_h { |i| ["k#{i}", "Option #{i}"] })
          @app.expect :call, [:text, "response", choices, nil], [@context]

          @middleware.call(@context)

          @context.input = "5"
          @app.expect :call, [:text, "response", nil, nil], [@context]

          @middleware.call(@context)

          assert_equal "k1", @context.input, "the id for the label \"5\" must win over position 5"
        end

        # The renderer truncates a button title to 20 chars, so a user who
        # types exactly what they see (rather than the full, untruncated
        # label the id was generated from) must still resolve.
        def test_typed_truncated_button_title_resolves
          long_label = "A label that is definitely longer than twenty chars"
          choices = {"a" => long_label, "b" => "Beta"}
          @app.expect :call, [:text, "response", choices, nil], [@context]

          @middleware.call(@context)

          @context.input = "A label that is d..." # 20 chars, as WhatsApp renders it on a button
          @app.expect :call, [:text, "response", nil, nil], [@context]

          @middleware.call(@context)

          assert_equal "a", @context.input
          @app.verify
        end

        # Above 3 choices WhatsApp renders a list instead of buttons, with a
        # 24 char row title cap instead of 20.
        def test_typed_truncated_list_row_title_resolves
          long_label = "A label that is definitely longer than twenty-four chars"
          choices = {"a" => long_label}.merge((2..4).to_h { |i| ["k#{i}", "Option #{i}"] })
          @app.expect :call, [:text, "response", choices, nil], [@context]

          @middleware.call(@context)

          @context.input = "A label that is defin..." # 24 chars, as WhatsApp renders it in a list row
          @app.expect :call, [:text, "response", nil, nil], [@context]

          @middleware.call(@context)

          assert_equal "a", @context.input
          @app.verify
        end

        # Two labels that truncate to the same displayed string must not
        # alias either: there is no way to tell which one the user meant.
        def test_colliding_truncated_titles_are_not_aliased
          choices = {
            "a" => "A label that is definitely one thing",
            "b" => "A label that is definitely another"
          }
          @app.expect :call, [:text, "response", choices, nil], [@context]

          @middleware.call(@context)

          assert_empty @session.get("whatsapp.alias_mapping"),
            "colliding truncated titles must not be aliased"

          @context.input = "A label that is d..."
          @app.expect :call, [:text, "response", nil, nil], [@context]

          @middleware.call(@context)

          assert_equal "A label that is d...", @context.input,
            "an ambiguous truncated title must pass through unresolved"
          @app.verify
        end

        # Precedence must be id, then alias, then position, no matter which
        # maps happen to hold the same key. Set up all three directly so the
        # test isolates resolution order from how each map gets populated.
        def test_generated_ids_win_over_aliases
          @session.set("whatsapp.choice_mapping", {"tied" => "from_id"})
          @session.set("whatsapp.alias_mapping", {"tied" => "from_alias"})
          @session.set("whatsapp.position_mapping", {"tied" => "from_position"})
          @context.input = "tied"
          @app.expect :call, [:text, "response", nil, nil], [@context]

          @middleware.call(@context)

          assert_equal "from_id", @context.input
          @app.verify
        end

        # Mirrors test_stale_position_map_does_not_hijack_a_later_free_text_digit:
        # resolving the alias rewrites @context.input to the choice key, which
        # no longer matches any stored map, so clear_mappings_if_needed clears
        # everything (including the alias map) before the next turn.
        def test_stale_alias_map_does_not_hijack_a_later_free_text_reply
          long_label = "A label that is definitely longer than twenty chars"
          choices = {"a" => long_label, "b" => "Beta"}
          @app.expect :call, [:text, "response", choices, nil], [@context]
          @middleware.call(@context)

          @context.input = "A label that is d..."
          @app.expect :call, [:text, "response", nil, nil], [@context]
          @middleware.call(@context)

          assert_equal "a", @context.input

          @context.input = "A label that is d..."
          @app.expect :call, [:prompt, "How many bags?", nil, nil], [@context]
          @middleware.call(@context)

          assert_equal "A label that is d...", @context.input,
            "a stale alias mapping must not rewrite free text on a later screen"
          @app.verify
        end

        def test_aliases_win_over_positions
          @session.set("whatsapp.alias_mapping", {"tied" => "from_alias"})
          @session.set("whatsapp.position_mapping", {"tied" => "from_position"})
          @context.input = "tied"
          @app.expect :call, [:text, "response", nil, nil], [@context]

          @middleware.call(@context)

          assert_equal "from_alias", @context.input
          @app.verify
        end

        # create_id_mapping only runs when the next screen has choices. A screen
        # with none (a plain prompt.ask) never touches the position map, so a
        # position map left over from an earlier numbered rung must be cleared
        # the moment it is consumed, not left to hijack a later free-text digit.
        def test_stale_position_map_does_not_hijack_a_later_free_text_digit
          choices = (1..25).to_h { |i| ["key#{i}", "Option #{i}"] }
          @app.expect :call, [:text, "response", choices, nil], [@context]

          @middleware.call(@context)

          @context.input = "3"
          @app.expect :call, [:text, "response", nil, nil], [@context]

          @middleware.call(@context)

          assert_equal "key3", @context.input

          @context.input = "3"
          @app.expect :call, [:prompt, "How many bags?", nil, nil], [@context]

          @middleware.call(@context)

          assert_equal "3", @context.input,
            "a typed digit on a screen with no choices must stay the digit, " \
            "but a stale position map rewrote it to #{@context.input.inspect}"
          @app.verify
        end

        # Mock classes for testing
        class MockSession
          def initialize
            @data = {}
          end

          def get(key)
            @data[key]
          end

          def set(key, value)
            @data[key] = value
          end

          def delete(key)
            @data.delete(key)
          end
        end

        class MockContext
          attr_accessor :input
          attr_reader :session

          def initialize(session)
            @session = session
            @data = {}
            @input = nil
          end

          def [](key)
            @data[key]
          end

          def []=(key, value)
            @data[key] = value
          end
        end
      end
    end
  end
end

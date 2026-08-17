require "test_helper"

module FlowChat
  module Http
    module Middleware
      class ChoiceMapperTest < Minitest::Test
        CHOICES = {"capture" => "Capturing leads", "onboard" => "Onboarding customers"}.freeze

        def setup
          @session = MockSession.new
          @context = MockContext.new(@session)
        end

        # Offer the choices, then answer them on the next turn.
        def answer(said, choices: CHOICES)
          turn { [:prompt, "Which one?", choices, nil] }

          @context.input = said
          seen = nil
          turn { |ctx|
            seen = ctx.input
            [:prompt, "Next", nil, nil]
          }
          seen
        end

        def turn(&app)
          ChoiceMapper.new(->(ctx) { app.call(ctx) }).call(@context)
        end

        def test_maps_the_label_that_was_pressed_to_the_key_the_flow_branches_on
          assert_equal "capture", answer("Capturing leads")
        end

        # Matching is exact, with no normalization on either side. A client
        # echoes back the string it was handed rather than a person typing it,
        # so nothing drifts on the way - and any transform that could absorb
        # such a drift can also merge two choices into one entry.
        def test_matching_is_exact
          assert_equal "onboarding customers", answer("onboarding customers"),
            "case must match"
          assert_equal "  Onboarding customers ", answer("  Onboarding customers "),
            "surrounding space must match"
        end

        def test_still_accepts_the_key_itself
          assert_equal "capture", answer("capture")
        end

        def test_leaves_free_text_alone
          assert_equal "none of these", answer("none of these")
        end

        def test_leaves_the_choices_as_the_flow_returned_them
          result = ChoiceMapper.new(->(_ctx) { [:prompt, "Which one?", CHOICES, nil] }).call(@context)

          assert_equal CHOICES, result[2]
        end

        def test_forgets_the_choices_once_the_question_has_moved_on
          turn { [:prompt, "Which one?", CHOICES, nil] }
          turn { [:prompt, "Your name?", nil, nil] }

          @context.input = "Capturing leads"
          seen = nil
          turn { |ctx|
            seen = ctx.input
            [:prompt, "Next", nil, nil]
          }

          assert_equal "Capturing leads", seen
        end

        # Two identical labels used to collapse into one mapping entry, and
        # the second choice could not be picked at all. They are numbered
        # instead, so each is nameable by what the visitor actually reads.
        def test_two_identical_labels_are_numbered_and_both_resolve
          duplicated = {"a" => "Same", "b" => "Same"}

          assert_equal "a", answer("1. Same", choices: duplicated)
          assert_equal "b", answer("2. Same", choices: duplicated)
        end

        # Because matching is exact, these are distinguishable and are left
        # alone - no numbering imposed on a set the client can round-trip.
        def test_labels_differing_only_by_case_are_left_unnumbered_and_both_resolve
          cased = {"a" => "Yes", "b" => "YES"}

          assert_equal "a", answer("Yes", choices: cased)
          assert_equal "b", answer("YES", choices: cased)
        end

        # The ordinary case is untouched: distinct labels are passed through
        # exactly as the flow wrote them, with no numbering imposed.
        def test_distinct_labels_are_passed_through_unnumbered
          rendered = nil
          turn { |_ctx| [:prompt, "Which one?", {"a" => "Alpha", "b" => "Beta"}, nil] }
            .tap { |result| rendered = result[2] }

          assert_equal({"a" => "Alpha", "b" => "Beta"}, rendered)
        end

        def test_leaves_blank_input_alone
          turn { [:prompt, "Which one?", CHOICES, nil] }
          @context.input = nil
          seen = :untouched
          turn { |ctx|
            seen = ctx.input
            [:prompt, "Next", nil, nil]
          }

          assert_nil seen
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
            @input = nil
          end
        end
      end
    end
  end
end

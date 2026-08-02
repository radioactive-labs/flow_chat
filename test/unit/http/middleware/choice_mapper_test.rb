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

        def test_is_not_fussy_about_case_or_surrounding_space
          assert_equal "onboard", answer("  onboarding customers ")
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

        def test_the_first_of_two_identical_labels_wins
          duplicated = {"a" => "Same", "b" => "Same"}

          assert_equal "a", answer("Same", choices: duplicated)
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

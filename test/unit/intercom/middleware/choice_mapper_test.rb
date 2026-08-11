require "test_helper"

module FlowChat
  module Intercom
    module Middleware
      class ChoiceMapperTest < Minitest::Test
        CHOICES = {"sales" => "Talk to sales", "support" => "Get support"}.freeze

        def setup
          @session = MockSession.new
          @context = MockContext.new(@session)
        end

        # Offer the choices, then answer them on the next turn.
        def answer(said, choices: CHOICES)
          turn { [:text, "Which one?", choices, nil] }

          @context.input = said
          seen = nil
          turn { |ctx|
            seen = ctx.input
            [:text, "Next", nil, nil]
          }
          seen
        end

        def turn(&app)
          ChoiceMapper.new(->(ctx) { app.call(ctx) }).call(@context)
        end

        def test_numbers_the_choices_for_the_renderer
          result = ChoiceMapper.new(->(_ctx) { [:text, "Which one?", CHOICES, nil] }).call(@context)

          assert_equal({"1" => "Talk to sales", "2" => "Get support"}, result[2])
        end

        def test_maps_the_number_that_was_replied_to_the_key
          assert_equal "support", answer("2")
        end

        def test_maps_the_label_too_since_intercom_is_a_text_box
          assert_equal "sales", answer("Talk to sales")
        end

        def test_is_not_fussy_about_case_or_surrounding_space
          assert_equal "support", answer("  get support ")
        end

        def test_leaves_free_text_alone
          assert_equal "neither thanks", answer("neither thanks")
        end

        def test_leaves_blank_input_alone
          turn { [:text, "Which one?", CHOICES, nil] }
          @context.input = nil
          seen = :untouched
          turn { |ctx|
            seen = ctx.input
            [:text, "Next", nil, nil]
          }

          assert_nil seen
        end

        def test_duplicated_labels_keep_distinct_numbers
          duplicated = {"a" => "Same", "b" => "Same"}
          turn { [:text, "Which one?", duplicated, nil] }

          @context.input = "2"
          seen = nil
          turn { |ctx|
            seen = ctx.input
            [:text, "Next", nil, nil]
          }

          assert_equal "b", seen
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

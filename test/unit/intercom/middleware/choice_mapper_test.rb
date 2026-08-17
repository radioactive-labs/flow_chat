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

        # Two choices reading the same are told apart by their numbers, which
        # is the whole reason a number is the only thing that resolves.
        def test_two_identical_labels_are_separated_by_their_numbers
          duplicated = {"a" => "Savings", "b" => "Savings"}

          assert_equal "a", answer("1", choices: duplicated)
          assert_equal "b", answer("2", choices: duplicated)
        end

        # The renderer is what numbers the list. Numbering the labels here too
        # produced a body reading "1. 1. Savings".
        def test_labels_are_not_numbered_before_the_renderer_numbers_them
          duplicated = {"a" => "Savings", "b" => "Savings"}
          result = ChoiceMapper.new(->(_ctx) { [:text, "Which?", duplicated, nil] }).call(@context)

          assert_equal({"1" => "Savings", "2" => "Savings"}, result[2])

          body = FlowChat::Intercom::Renderer.new("Which?", choices: result[2]).render[1]
          assert_includes body, "1. Savings"
          refute_includes body, "1. 1. Savings"
        end

        # A map left live into a free-text screen rewrote an answer there into
        # the previous menu's key. WhatsApp and Messenger each had this fixed
        # twice; Intercom never cleared its map at all.
        def test_the_mapping_is_cleared_once_a_screen_carries_no_choices
          turn { [:text, "Which one?", CHOICES, nil] }
          turn { [:text, "Your name?", nil, nil] }

          @context.input = "Talk to sales"
          seen = nil
          turn { |ctx|
            seen = ctx.input
            [:text, "Next", nil, nil]
          }

          assert_equal "Talk to sales", seen,
            "a stale choice mapping must not rewrite free text on a later screen"
        end

        def test_numbers_the_choices_for_the_renderer
          result = ChoiceMapper.new(->(_ctx) { [:text, "Which one?", CHOICES, nil] }).call(@context)

          assert_equal({"1" => "Talk to sales", "2" => "Get support"}, result[2])
        end

        def test_maps_the_number_that_was_replied_to_the_key
          assert_equal "support", answer("2")
        end

        # A number is the only thing that resolves, as on USSD, and it is what
        # the message asks for. Labels used to resolve too, which is what made
        # two choices reading the same collapse onto one entry.
        def test_a_label_does_not_resolve
          assert_equal "Talk to sales", answer("Talk to sales")
        end

        # Trimming a chat message cannot merge two choices the way folding
        # labels could: "1" and "2" are as distinct after it as before.
        def test_is_not_fussy_about_surrounding_space
          assert_equal "support", answer("  2 ")
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

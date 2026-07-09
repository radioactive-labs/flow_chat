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

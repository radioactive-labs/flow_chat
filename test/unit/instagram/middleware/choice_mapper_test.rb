require "test_helper"

module FlowChat
  module Instagram
    module Middleware
      class ChoiceMapperTest < Minitest::Test
        def setup
          @app = Minitest::Mock.new
          @middleware = ChoiceMapper.new(@app)
          @session = MockSession.new
          @context = MockContext.new(@session)
        end

        def test_tapped_quick_reply_resolves_to_the_original_key
          choices = {"create" => "Create Account", "login" => "Log In"}
          @app.expect :call, [:prompt, "Pick", choices, nil], [@context]

          @middleware.call(@context)

          tapped = @session.get("instagram.choice_mapping").keys.first
          @context.input = tapped
          @app.expect :call, [:text, "response", nil, nil], [@context]

          @middleware.call(@context)

          assert_equal "create", @context.input
          @app.verify
        end

        # Unlike Messenger, Instagram always numbers the body, so a position
        # map must exist even on the quick-reply rung: a typed number is a
        # valid reply on every screen with choices, not only above the
        # carousel capacity.
        def test_position_map_exists_on_the_quick_reply_rung
          choices = {"a" => "Alpha", "b" => "Beta"}
          @app.expect :call, [:prompt, "Pick", choices, nil], [@context]

          @middleware.call(@context)

          assert_equal "a", @session.get("instagram.position_mapping")["1"]
          assert_equal "b", @session.get("instagram.position_mapping")["2"]
          @app.verify
        end

        def test_typed_number_resolves_on_the_carousel_rung
          choices = (1..14).to_h { |i| ["k#{i}", "Option #{i}"] }
          @app.expect :call, [:prompt, "Pick", choices, nil], [@context]

          @middleware.call(@context)

          @context.input = "3"
          @app.expect :call, [:text, "response", nil, nil], [@context]

          @middleware.call(@context)

          assert_equal "k3", @context.input
          @app.verify
        end

        # A generated id and a position occupy the same key space, so ids
        # must be resolved first. See the equivalent Messenger test for the
        # full mechanism; the risk is higher here because the position map
        # is live at every rung, not only above the carousel capacity.
        def test_generated_ids_win_over_positions
          choices = {"special" => "5"}.merge((1..4).to_h { |i| ["k#{i}", "Option #{i}"] })
          @app.expect :call, [:prompt, "Pick", choices, nil], [@context]

          @middleware.call(@context)

          assert_equal "k4", @session.get("instagram.position_mapping")["5"],
            "test setup assumption: position 5 is the choice \"k4\""

          @context.input = "5"
          @app.expect :call, [:text, "response", nil, nil], [@context]

          @middleware.call(@context)

          assert_equal "special", @context.input, "the id for the label \"5\" must win over position 5"
          @app.verify
        end

        # The always-on position map raises the stakes for the WhatsApp
        # clearing bug (Task 6) and its Messenger mirror (Task 13): on
        # Instagram a position map exists after EVERY menu, not only above
        # the carousel capacity, so a mapper that fails to clear it hijacks
        # every typed digit on every screen that follows a menu, not just
        # some of them.
        def test_stale_maps_do_not_hijack_a_later_free_text_digit
          choices = {"a" => "Alpha", "b" => "Beta"}
          @app.expect :call, [:prompt, "Pick", choices, nil], [@context]

          @middleware.call(@context)

          @context.input = "2"
          @app.expect :call, [:prompt, "How many bags?", nil, nil], [@context]

          @middleware.call(@context)

          assert_equal "b", @context.input

          @context.input = "2"
          @app.expect :call, [:text, "response", nil, nil], [@context]

          @middleware.call(@context)

          assert_equal "2", @context.input,
            "a typed digit on a screen with no choices must stay the digit, " \
            "but a stale mapping rewrote it to #{@context.input.inspect}"
          @app.verify
        end

        def test_gateway_exposes_the_instagram_hooks
          config = FlowChat::Instagram::Configuration.new(nil)
          config.page_id = "page_1"
          config.access_token = "tok"
          config.verify_token = "verify"

          gateway = FlowChat::Instagram::Gateway::SendApi.new(proc {}, config)

          assert_equal :instagram, gateway.platform
          assert_equal :instagram_send_api, gateway.gateway_name
          assert_equal FlowChat::Instagram::Renderer, gateway.renderer_class
          assert_equal FlowChat::Instagram::Middleware::ChoiceMapper,
            FlowChat::Instagram::Gateway::SendApi.choice_mapper_class
        end

        # Mock classes for testing, mirroring
        # test/unit/messenger/middleware/choice_mapper_test.rb.
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

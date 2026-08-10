require "test_helper"

module FlowChat
  module Messenger
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

          tapped = @session.get("messenger.choice_mapping").keys.first
          @context.input = tapped
          @app.expect :call, [:text, "response", nil, nil], [@context]

          @middleware.call(@context)

          assert_equal "create", @context.input
          @app.verify
        end

        def test_typed_number_resolves_on_the_numbered_rung
          choices = (1..31).to_h { |i| ["k#{i}", "Option #{i}"] }
          @app.expect :call, [:prompt, "Pick", choices, nil], [@context]

          @middleware.call(@context)

          @context.input = "3"
          @app.expect :call, [:text, "response", nil, nil], [@context]

          @middleware.call(@context)

          assert_equal "k3", @context.input
          @app.verify
        end

        # A generated id and a position occupy the same key space:
        # IdGenerator#normalize_label keeps \w, which includes digits, so a
        # choice labelled "5" generates the id "5". Ids must win: the id map is
        # consulted before the position map.
        #
        # The collision only exists once a position map exists at all, which
        # on Messenger's ladder means more than 30 choices (the numbered
        # rung). A "special" choice labelled "5" sits first (position "1"),
        # while a different choice, "k4", sits at position "5" - so typing
        # "5" finds two different answers depending on which map wins.
        def test_generated_ids_win_over_positions
          choices = {"special" => "5"}.merge((1..30).to_h { |i| ["k#{i}", "Option #{i}"] })
          @app.expect :call, [:prompt, "Pick", choices, nil], [@context]

          @middleware.call(@context)

          assert_equal "k4", @session.get("messenger.position_mapping")["5"],
            "test setup assumption: position 5 is the choice \"k4\""

          @context.input = "5"
          @app.expect :call, [:text, "response", nil, nil], [@context]

          @middleware.call(@context)

          assert_equal "special", @context.input, "the id for the label \"5\" must win over position 5"
          @app.verify
        end

        def test_no_position_map_on_the_quick_reply_rung
          choices = {"a" => "Alpha", "b" => "Beta"}
          @app.expect :call, [:prompt, "Pick", choices, nil], [@context]

          @middleware.call(@context)

          assert_nil @session.get("messenger.position_mapping")
          @app.verify
        end

        # Both maps must clear together. create_mappings only runs when the
        # next screen HAS choices, so a screen without them clears nothing
        # unless clearing is explicit. This was a real bug in the WhatsApp
        # mapper, found and fixed in Task 6: read
        # lib/flow_chat/whatsapp/middleware/choice_mapper.rb for the mechanism
        # this mirrors. The turn that ADVANCES the flow (here, the turn that
        # resolves the tapped "3") is the one whose app returns the
        # choice-less prompt, matching the WhatsApp regression test.
        def test_stale_maps_do_not_hijack_a_later_free_text_digit
          choices = (1..31).to_h { |i| ["k#{i}", "Option #{i}"] }
          @app.expect :call, [:prompt, "Pick", choices, nil], [@context]

          @middleware.call(@context)

          @context.input = "3"
          @app.expect :call, [:prompt, "How many bags?", nil, nil], [@context]

          @middleware.call(@context)

          assert_equal "k3", @context.input

          @context.input = "3"
          @app.expect :call, [:text, "response", nil, nil], [@context]

          @middleware.call(@context)

          assert_equal "3", @context.input,
            "a typed digit on a screen with no choices must stay the digit, " \
            "but a stale mapping rewrote it to #{@context.input.inspect}"
          @app.verify
        end

        def test_gateway_exposes_the_messenger_hooks
          config = FlowChat::Messenger::Configuration.new(nil)
          config.page_id = "page_1"
          config.access_token = "tok"
          config.verify_token = "verify"

          gateway = FlowChat::Messenger::Gateway::SendApi.new(proc {}, config)

          assert_equal :messenger, gateway.platform
          assert_equal :messenger_send_api, gateway.gateway_name
          assert_equal FlowChat::Messenger::Renderer, gateway.renderer_class
          assert_equal FlowChat::Messenger::Middleware::ChoiceMapper,
            FlowChat::Messenger::Gateway::SendApi.choice_mapper_class
        end

        # Mock classes for testing, mirroring
        # test/unit/whatsapp/middleware/choice_mapper_test.rb.
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

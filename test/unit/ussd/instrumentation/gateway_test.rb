# Tests USSD gateway instrumentation for message received and sent events
require "test_helper"

module FlowChat
  module Ussd
    module Instrumentation
      class GatewayTest < Minitest::Test
        def setup
          @original_notifications = ActiveSupport::Notifications.notifier
          @test_events = []

          # Create a test notifier that captures events
          @test_notifier = ActiveSupport::Notifications::Fanout.new
          @test_notifier.subscribe(/.*flow_chat$/) do |name, start, finish, id, payload|
            @test_events << {
              name: name,
              start: start,
              finish: finish,
              id: id,
              payload: payload,
              duration: (finish - start) * 1000
            }
          end

          ActiveSupport::Notifications.instance_variable_set(:@notifier, @test_notifier)

          @context = FlowChat::Context.new
          @context["request.msisdn"] = "+256700123456"
          @context["request.id"] = "test_session_123"
          @context["session.id"] = "ussd:test_session_123"
          @context.session = create_test_session_store
        end

        def teardown
          ActiveSupport::Notifications.instance_variable_set(:@notifier, @original_notifications)
          @test_events.clear
        end

        def test_nalo_gateway_instruments_message_received
          # Mock controller and request
          controller = Object.new
          request = Object.new
          params = {
            "USERID" => "test_session_123",
            "MSISDN" => "256700123456",
            "USERDATA" => "1",
            "SESSIONID" => "1"
          }

          def request.params
            @params
          end

          def request.params=(p)
            @params = p
          end
          request.params = params

          def controller.request
            @request
          end

          def controller.request=(r)
            @request = r
          end

          def controller.render(opts)
            @rendered = opts
          end

          controller.request = request

          # Create gateway
          app = ->(context) { "Test response" }
          gateway = FlowChat::Ussd::Gateway::Nalo.new(app)

          # Update context with controller
          @context["controller"] = controller

          # Call gateway
          gateway.call(@context)

          # Find message received event
          received_event = @test_events.find { |e| e[:name] == "message.received.flow_chat" }

          assert received_event, "Should have instrumented message received"
          assert_equal "+256700123456", received_event[:payload][:from]
          assert_equal "1", received_event[:payload][:message]
          assert received_event[:payload][:timestamp]
        end

        def test_nalo_gateway_instruments_message_sent
          # Mock controller
          controller = Object.new
          request = Object.new
          params = {"USERID" => "test_session_123", "MSISDN" => "256700123456", "USERDATA" => ""}

          def request.params
            @params
          end

          def request.params=(p)
            @params = p
          end
          request.params = params

          def controller.request
            @request
          end

          def controller.request=(r)
            @request = r
          end

          def controller.render(opts)
            @rendered = opts
          end

          def controller.rendered
            @rendered
          end

          controller.request = request

          # Create gateway - app.call returns [type, prompt, choices, media]
          app = ->(context) {
            [:prompt, "Test message", nil, nil]
          }
          gateway = FlowChat::Ussd::Gateway::Nalo.new(app)

          # Update context with controller
          @context["controller"] = controller

          # Call gateway
          gateway.call(@context)

          # Find message sent event
          sent_event = @test_events.find { |e| e[:name] == "message.sent.flow_chat" }

          assert sent_event, "Should have instrumented message sent"
          assert_equal "+256700123456", sent_event[:payload][:to]
          assert_equal "", sent_event[:payload][:message]  # This is the input message, not output
          assert_equal "prompt", sent_event[:payload][:message_type]
          assert_equal :nalo, sent_event[:payload][:gateway]
          assert_equal :ussd, sent_event[:payload][:platform]
        end

        def test_nalo_gateway_instruments_both_received_and_sent_with_input
          # Mock controller with input
          controller = Object.new
          request = Object.new
          params = {
            "USERID" => "test_session_123",
            "MSISDN" => "256700123456",
            "USERDATA" => "John Doe",
            "SESSIONID" => "1"
          }

          def request.params
            @params
          end

          def request.params=(p)
            @params = p
          end
          request.params = params

          def controller.request
            @request
          end

          def controller.request=(r)
            @request = r
          end

          def controller.render(opts)
            @rendered = opts
          end

          controller.request = request

          # Create gateway - returns terminal response
          app = ->(context) {
            [:terminal, "Goodbye #{context["request.input"]}", nil, nil]
          }
          gateway = FlowChat::Ussd::Gateway::Nalo.new(app)

          # Update context with controller
          @context["controller"] = controller

          # Call gateway
          gateway.call(@context)

          # Check both events were triggered
          assert @test_events.any? { |e| e[:name] == "message.received.flow_chat" }
          assert @test_events.any? { |e| e[:name] == "message.sent.flow_chat" }

          # Check sent event has correct payload
          sent_event = @test_events.find { |e| e[:name] == "message.sent.flow_chat" }
          assert_equal "John Doe", sent_event[:payload][:message]  # This is the input message
          assert_equal "terminal", sent_event[:payload][:message_type]
        end

        private

        def create_test_session_store
          store = Object.new

          def store.data
            @data ||= {}
          end

          def store.get(key)
            data[key]
          end

          def store.set(key, value)
            data[key] = value
          end

          def store.delete(key)
            data.delete(key)
          end

          store
        end
      end
    end
  end
end

# Tests the integrity and completeness of USSD instrumentation events
require "test_helper"

module FlowChat
  module Ussd
    module Instrumentation
      class EventIntegrityTest < Minitest::Test
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
              payload: payload
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

        def test_all_event_types_are_instrumented
          # Test that all expected event types can be triggered
          expected_events = [
            "message.sent.flow_chat",
            "context.created.flow_chat"
          ]

          # Trigger various events through actual middleware usage
          trigger_all_events

          # Check that we have at least one of each expected event
          expected_events.each do |event_name|
            assert @test_events.any? { |e| e[:name] == event_name },
              "Expected to find event: #{event_name}"
          end
        end

        def test_instrumentation_payload_data_integrity
          # Test that payloads contain expected data and are properly structured
          params = {
            "USERID" => "integrity_test_123",
            "MSISDN" => "256700999888",
            "USERDATA" => "Test Input",
            "SESSIONID" => "999"
          }

          controller = create_mock_controller(params)

          # Create gateway with app that sets response
          app = ->(context) {
            [:terminal, "Test Response", nil, {type: :image, url: "http://test.com/img.jpg"}]
          }

          gateway = FlowChat::Ussd::Gateway::Nalo.new(app)

          # Update context with controller
          @context["controller"] = controller

          # Reset context IDs that will be set by gateway
          @context["request.id"] = nil
          @context["session.id"] = nil

          # Call gateway
          gateway.call(@context)

          # Check received event payload
          received = @test_events.find { |e| e[:name] == "message.received.flow_chat" }
          assert received
          assert_equal "+256700999888", received[:payload][:from]
          assert_equal "Test Input", received[:payload][:message]
          assert received[:payload][:timestamp]

          # Check sent event payload
          sent = @test_events.find { |e| e[:name] == "message.sent.flow_chat" }
          assert sent
          assert_equal "+256700999888", sent[:payload][:to]
          assert_equal "Test Input", sent[:payload][:message]  # Input message, not output
          assert_equal "terminal", sent[:payload][:message_type]
          assert_equal :nalo, sent[:payload][:gateway]
          assert_equal :ussd, sent[:payload][:platform]
          assert_equal "integrity_test_123", sent[:payload][:session_id]

          # Verify expected keys are present
          expected_received_keys = [:from, :message, :timestamp]
          expected_sent_keys = [:to, :session_id, :message, :message_type, :gateway, :platform, :content_length, :timestamp]

          expected_received_keys.each do |key|
            assert received[:payload].key?(key), "Expected received payload to have key: #{key}"
          end

          expected_sent_keys.each do |key|
            assert sent[:payload].key?(key), "Expected sent payload to have key: #{key}"
          end
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

        def create_mock_controller(params = nil)
          controller = Object.new
          request = Object.new
          params ||= {
            "USERID" => "test_session_123",
            "MSISDN" => "256700123456",
            "USERDATA" => "",
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

          def controller.rendered
            @rendered
          end

          controller.request = request
          controller
        end

        def trigger_all_events
          # Trigger gateway events
          controller = create_mock_controller

          # Set up context with input to trigger message.received event
          @context["request.input"] = "test input"
          @context["controller"] = controller

          app = ->(ctx) {
            [:prompt, "Test", nil, nil]
          }
          gateway = FlowChat::Ussd::Gateway::Nalo.new(app)
          gateway.call(@context)

          # Trigger pagination events
          @context["request.input"] = ""
          @context["response.text"] = "1. Option\n98. More"
          @context["ussd.pagination.active"] = true
          @context["ussd.pagination.page"] = 1
          @context["ussd.pagination.total_pages"] = 2

          pagination_app = ->(ctx) { ctx }
          pagination = FlowChat::Ussd::Middleware::Pagination.new(pagination_app)

          # Ensure controller is still set
          @context["controller"] = controller

          pagination.call(@context)
        end
      end
    end
  end
end

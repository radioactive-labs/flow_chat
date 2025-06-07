require "test_helper"

class InstrumentationTest < Minitest::Test
  def setup
    @original_notifications = ActiveSupport::Notifications.notifier
    @test_events = []

    # Create a test notifier that captures events
    @test_notifier = ActiveSupport::Notifications::Fanout.new
    @test_notifier.subscribe(/flow_chat$/) do |name, start, finish, id, payload|
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
  end

  def teardown
    ActiveSupport::Notifications.instance_variable_set(:@notifier, @original_notifications)
    FlowChat::Instrumentation::Setup.reset!
  end

  def test_instrumentation_module_constants_exist
    assert_includes FlowChat::Instrumentation::Events.constants, :FLOW_EXECUTION_START
    assert_includes FlowChat::Instrumentation::Events.constants, :SESSION_CREATED
    assert_includes FlowChat::Instrumentation::Events.constants, :MESSAGE_SENT
    assert_includes FlowChat::Instrumentation::Events.constants, :MESSAGE_RECEIVED
    assert_includes FlowChat::Instrumentation::Events.constants, :PAGINATION_TRIGGERED
  end

  def test_instrumentation_module_included_properly
    test_class = Class.new do
      include FlowChat::Instrumentation
    end

    instance = test_class.new
    assert_respond_to instance, :instrument
  end

  def test_instrument_method_publishes_event
    test_class = Class.new do
      include FlowChat::Instrumentation

      def test_method
        instrument("test.event", {key: "value"}) do
          "test_result"
        end
      end
    end

    instance = test_class.new
    result = instance.test_method

    assert_equal "test_result", result
    assert_equal 1, @test_events.size

    event = @test_events.first
    assert_equal "test.event.flow_chat", event[:name]
    assert_equal "value", event[:payload][:key]
    assert event[:payload][:timestamp]
    assert event[:duration] >= 0
  end

  def test_instrument_with_context_enrichment
    context = FlowChat::Context.new
    context["session.id"] = "test_session_123"
    context["flow.name"] = "TestFlow"
    context["request.gateway"] = :test_gateway

    test_class = Class.new do
      include FlowChat::Instrumentation

      attr_reader :context

      def initialize(context)
        @context = context
      end

      def test_method
        instrument("test.enriched", {custom: "data"})
      end
    end

    # Clear any existing events
    @test_events.clear

    instance = test_class.new(context)
    instance.test_method

    # Find the event we're looking for
    test_event = @test_events.find { |e| e[:name] == "test.enriched.flow_chat" }
    refute_nil test_event, "Expected to find test.enriched.flow_chat event"

    payload = test_event[:payload]

    assert_equal "test_session_123", payload[:session_id]
    assert_equal "TestFlow", payload[:flow_name]
    assert_equal :test_gateway, payload[:gateway]
    assert_equal "data", payload[:custom]
  end

  def test_instrument_with_exception
    test_class = Class.new do
      include FlowChat::Instrumentation

      def test_method_with_error
        instrument("test.error") do
          raise StandardError, "Test error"
        end
      end
    end

    instance = test_class.new

    assert_raises(StandardError) do
      instance.test_method_with_error
    end

    # Event should still be published even with exception
    assert_equal 1, @test_events.size
    event = @test_events.first
    assert_equal "test.error.flow_chat", event[:name]
  end

  def test_instrument_without_block
    test_class = Class.new do
      include FlowChat::Instrumentation

      def test_method_no_block
        instrument("test.no.block", {data: "test"})
      end
    end

    instance = test_class.new
    result = instance.test_method_no_block

    assert_nil result
    assert_equal 1, @test_events.size

    event = @test_events.first
    assert_equal "test.no.block.flow_chat", event[:name]
    assert_equal "test", event[:payload][:data]
  end

  def test_predefined_event_constants
    events = FlowChat::Instrumentation::Events

    # Core framework events
    assert_equal "flow.execution.start", events::FLOW_EXECUTION_START
    assert_equal "flow.execution.end", events::FLOW_EXECUTION_END
    assert_equal "flow.execution.error", events::FLOW_EXECUTION_ERROR

    # Session events
    assert_equal "session.created", events::SESSION_CREATED
    assert_equal "session.destroyed", events::SESSION_DESTROYED

    # New platform-agnostic events
    assert_equal "message.received", events::MESSAGE_RECEIVED
    assert_equal "message.sent", events::MESSAGE_SENT
    assert_equal "pagination.triggered", events::PAGINATION_TRIGGERED
    assert_equal "webhook.verified", events::WEBHOOK_VERIFIED
    assert_equal "webhook.failed", events::WEBHOOK_FAILED
    assert_equal "media.upload", events::MEDIA_UPLOAD
  end
end

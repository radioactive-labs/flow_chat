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
    assert_equal "api.error", events::API_ERROR
  end

  # ============================================================================
  # REPORT_API_ERROR TESTS
  # ============================================================================

  def test_report_api_error_instruments_api_error_event
    @test_events.clear

    FlowChat::Instrumentation.report_api_error(
      "Test API error",
      platform: :test_platform,
      endpoint: "/api/test"
    )

    event = @test_events.find { |e| e[:name] == "api.error.flow_chat" }
    refute_nil event, "Expected to find api.error.flow_chat event"

    assert_equal "Test API error", event[:payload][:message]
    assert_equal :test_platform, event[:payload][:platform]
    assert_equal "/api/test", event[:payload][:endpoint]
    assert event[:payload][:timestamp]
  end

  def test_report_api_error_with_exception
    @test_events.clear

    original_error = StandardError.new("Original error message")

    FlowChat::Instrumentation.report_api_error(
      "Wrapped error",
      error: original_error,
      platform: :whatsapp,
      recipient: "+1234567890"
    )

    event = @test_events.find { |e| e[:name] == "api.error.flow_chat" }
    refute_nil event

    assert_equal "Wrapped error", event[:payload][:message]
    assert_equal :whatsapp, event[:payload][:platform]
    assert_equal "+1234567890", event[:payload][:recipient]
  end

  def test_report_api_error_compacts_nil_values
    @test_events.clear

    FlowChat::Instrumentation.report_api_error(
      "Error with nils",
      platform: :telegram,
      chat_id: nil,
      error_code: 401
    )

    event = @test_events.find { |e| e[:name] == "api.error.flow_chat" }
    refute_nil event

    refute event[:payload].key?(:chat_id), "Expected nil values to be compacted"
    assert_equal 401, event[:payload][:error_code]
  end

  def test_report_api_error_reports_to_rails_error_when_available
    @test_events.clear

    reported_errors = []

    # Create a simple mock Rails.error object
    mock_rails_error = Object.new
    mock_rails_error.define_singleton_method(:respond_to?) { |method| method == :report }
    mock_rails_error.define_singleton_method(:report) do |exception, handled:, context:|
      reported_errors << {exception: exception, handled: handled, context: context}
    end

    mock_rails = Module.new do
      define_singleton_method(:respond_to?) { |method| method == :error }
    end
    mock_rails.define_singleton_method(:error) { mock_rails_error }

    original_rails = defined?(Rails) ? Rails : nil
    Object.send(:remove_const, :Rails) if defined?(Rails)
    Object.const_set(:Rails, mock_rails)

    begin
      FlowChat::Instrumentation.report_api_error(
        "Intercom error",
        platform: :intercom,
        conversation_id: "conv_123"
      )

      assert_equal 1, reported_errors.size
      assert reported_errors.first[:exception].is_a?(StandardError)
      assert_equal "Intercom error", reported_errors.first[:exception].message
      assert_equal true, reported_errors.first[:handled]
      assert_equal :intercom, reported_errors.first[:context][:platform]
    ensure
      Object.send(:remove_const, :Rails)
      Object.const_set(:Rails, original_rails) if original_rails
    end
  end

  def test_report_api_error_uses_provided_exception_for_rails_error
    @test_events.clear

    original_exception = ArgumentError.new("Bad argument")
    reported_errors = []

    mock_rails_error = Object.new
    mock_rails_error.define_singleton_method(:respond_to?) { |method| method == :report }
    mock_rails_error.define_singleton_method(:report) do |exception, handled:, context:|
      reported_errors << {exception: exception, handled: handled, context: context}
    end

    mock_rails = Module.new do
      define_singleton_method(:respond_to?) { |method| method == :error }
    end
    mock_rails.define_singleton_method(:error) { mock_rails_error }

    original_rails = defined?(Rails) ? Rails : nil
    Object.send(:remove_const, :Rails) if defined?(Rails)
    Object.const_set(:Rails, mock_rails)

    begin
      FlowChat::Instrumentation.report_api_error(
        "Error with exception",
        error: original_exception,
        platform: :telegram
      )

      assert_equal 1, reported_errors.size
      assert_same original_exception, reported_errors.first[:exception]
      assert_equal true, reported_errors.first[:handled]
    ensure
      Object.send(:remove_const, :Rails)
      Object.const_set(:Rails, original_rails) if original_rails
    end
  end

  def test_report_api_error_works_without_rails
    @test_events.clear

    # Ensure Rails is not defined
    original_rails = Rails if defined?(Rails)
    Object.send(:remove_const, :Rails) if defined?(Rails)

    begin
      # Should not raise
      FlowChat::Instrumentation.report_api_error(
        "Error without Rails",
        platform: :whatsapp
      )

      event = @test_events.find { |e| e[:name] == "api.error.flow_chat" }
      refute_nil event
      assert_equal "Error without Rails", event[:payload][:message]
    ensure
      Object.const_set(:Rails, original_rails) if original_rails
    end
  end
end

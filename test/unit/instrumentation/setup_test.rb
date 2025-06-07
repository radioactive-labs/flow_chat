require "test_helper"

class SetupTest < Minitest::Test
  def setup
    # Reset setup state before each test
    FlowChat::Instrumentation::Setup.reset!
  end

  def teardown
    FlowChat::Instrumentation::Setup.reset!
  end

  def test_setup_logging_initializes_log_subscriber
    refute FlowChat::Instrumentation::Setup.instance_variable_get(:@log_subscriber_setup)

    FlowChat::Instrumentation::Setup.setup_logging!

    assert FlowChat::Instrumentation::Setup.instance_variable_get(:@log_subscriber_setup)
    assert FlowChat::Instrumentation::Setup.instance_variable_get(:@log_subscriber)
  end

  def test_setup_metrics_initializes_metrics_collector
    refute FlowChat::Instrumentation::Setup.instance_variable_get(:@metrics_collector_setup)

    FlowChat::Instrumentation::Setup.setup_metrics!

    assert FlowChat::Instrumentation::Setup.instance_variable_get(:@metrics_collector_setup)
    assert FlowChat::Instrumentation::Setup.instance_variable_get(:@metrics_collector)
  end

  def test_setup_instrumentation_initializes_both
    FlowChat::Instrumentation::Setup.setup_instrumentation!

    assert FlowChat::Instrumentation::Setup.instance_variable_get(:@log_subscriber_setup)
    assert FlowChat::Instrumentation::Setup.instance_variable_get(:@metrics_collector_setup)
    assert FlowChat::Instrumentation::Setup.instance_variable_get(:@log_subscriber)
    assert FlowChat::Instrumentation::Setup.instance_variable_get(:@metrics_collector)
  end

  def test_setup_logging_is_idempotent
    FlowChat::Instrumentation::Setup.setup_logging!
    first_subscriber = FlowChat::Instrumentation::Setup.instance_variable_get(:@log_subscriber)

    FlowChat::Instrumentation::Setup.setup_logging!
    second_subscriber = FlowChat::Instrumentation::Setup.instance_variable_get(:@log_subscriber)

    assert_same first_subscriber, second_subscriber
  end

  def test_setup_metrics_is_idempotent
    FlowChat::Instrumentation::Setup.setup_metrics!
    first_collector = FlowChat::Instrumentation::Setup.instance_variable_get(:@metrics_collector)

    FlowChat::Instrumentation::Setup.setup_metrics!
    second_collector = FlowChat::Instrumentation::Setup.instance_variable_get(:@metrics_collector)

    assert_same first_collector, second_collector
  end

  def test_metrics_collector_accessor
    # Should create new instance if not setup
    collector1 = FlowChat::Instrumentation::Setup.metrics_collector
    assert_instance_of FlowChat::Instrumentation::MetricsCollector, collector1

    # Should return same instance on subsequent calls
    collector2 = FlowChat::Instrumentation::Setup.metrics_collector
    assert_same collector1, collector2
  end

  def test_reset_clears_all_setup_state
    FlowChat::Instrumentation::Setup.setup_instrumentation!

    # Verify setup
    assert FlowChat::Instrumentation::Setup.instance_variable_get(:@log_subscriber_setup)
    assert FlowChat::Instrumentation::Setup.instance_variable_get(:@metrics_collector_setup)
    assert FlowChat::Instrumentation::Setup.instance_variable_get(:@log_subscriber)
    assert FlowChat::Instrumentation::Setup.instance_variable_get(:@metrics_collector)

    # Reset
    FlowChat::Instrumentation::Setup.reset!

    # Verify reset
    refute FlowChat::Instrumentation::Setup.instance_variable_get(:@log_subscriber_setup)
    refute FlowChat::Instrumentation::Setup.instance_variable_get(:@metrics_collector_setup)
    assert_nil FlowChat::Instrumentation::Setup.instance_variable_get(:@log_subscriber)
    assert_nil FlowChat::Instrumentation::Setup.instance_variable_get(:@metrics_collector)
  end

  def test_log_subscriber_subscribes_to_events
    # Mock ActiveSupport::Notifications to track subscriptions
    subscriptions = []
    original_subscribe = ActiveSupport::Notifications.method(:subscribe)

    ActiveSupport::Notifications.define_singleton_method(:subscribe) do |pattern, &block|
      subscriptions << pattern
      original_subscribe.call(pattern, &block)
    end

    FlowChat::Instrumentation::Setup.setup_logging!

    # Verify key events are subscribed
    expected_events = [
      "flow.execution.start.flow_chat",
      "flow.execution.end.flow_chat",
      "flow.execution.error.flow_chat",
      "session.created.flow_chat",
      "session.destroyed.flow_chat",
      "message.received.flow_chat",
      "message.sent.flow_chat",
      "webhook.verified.flow_chat",
      "pagination.triggered.flow_chat"
    ]

    expected_events.each do |event|
      assert_includes subscriptions, event, "Expected subscription to #{event}"
    end

    # Restore original method
    ActiveSupport::Notifications.define_singleton_method(:subscribe, original_subscribe)
  end

  def test_can_call_setup_methods_in_any_order
    # Can setup metrics first, then logging
    FlowChat::Instrumentation::Setup.setup_metrics!
    FlowChat::Instrumentation::Setup.setup_logging!

    assert FlowChat::Instrumentation::Setup.instance_variable_get(:@log_subscriber_setup)
    assert FlowChat::Instrumentation::Setup.instance_variable_get(:@metrics_collector_setup)

    FlowChat::Instrumentation::Setup.reset!

    # Can setup logging first, then metrics
    FlowChat::Instrumentation::Setup.setup_logging!
    FlowChat::Instrumentation::Setup.setup_metrics!

    assert FlowChat::Instrumentation::Setup.instance_variable_get(:@log_subscriber_setup)
    assert FlowChat::Instrumentation::Setup.instance_variable_get(:@metrics_collector_setup)
  end

  def test_setup_with_options
    options = {test_option: "test_value"}

    # Methods should accept options without error
    FlowChat::Instrumentation::Setup.setup_logging!(options)
    FlowChat::Instrumentation::Setup.setup_metrics!(options)
    FlowChat::Instrumentation::Setup.setup_instrumentation!(options)

    # All should be set up successfully
    assert FlowChat::Instrumentation::Setup.instance_variable_get(:@log_subscriber_setup)
    assert FlowChat::Instrumentation::Setup.instance_variable_get(:@metrics_collector_setup)
  end

  def test_log_subscriber_responds_to_event_methods
    FlowChat::Instrumentation::Setup.setup_logging!
    subscriber = FlowChat::Instrumentation::Setup.instance_variable_get(:@log_subscriber)

    # Verify key event handler methods exist
    expected_methods = [
      :flow_execution_start,
      :flow_execution_end,
      :flow_execution_error,
      :session_created,
      :session_destroyed,
      :message_received,
      :message_sent,
      :webhook_verified,
      :pagination_triggered,
      :context_created
    ]

    expected_methods.each do |method|
      assert_respond_to subscriber, method, "Expected LogSubscriber to respond to #{method}"
    end
  end

  def test_non_rails_environment_immediate_initialization
    # Temporarily undefine Rails if it exists
    original_rails = defined?(Rails) ? Rails : nil
    Object.send(:remove_const, :Rails) if defined?(Rails)

    FlowChat::Instrumentation::Setup.setup_logging!

    # Should initialize immediately in non-Rails environment
    assert FlowChat::Instrumentation::Setup.instance_variable_get(:@log_subscriber)

    # Restore Rails if it existed
    Object.const_set(:Rails, original_rails) if original_rails
  end
end

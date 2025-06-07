require "test_helper"

class MetricsCollectorTest < Minitest::Test
  def setup
    @original_notifications = ActiveSupport::Notifications.notifier
    @collector = FlowChat::Instrumentation::MetricsCollector.new
  end

  def teardown
    ActiveSupport::Notifications.instance_variable_set(:@notifier, @original_notifications)
  end

  def test_initializes_with_empty_metrics
    metrics = @collector.snapshot
    assert_empty metrics
  end

  def test_flow_execution_end_increments_counters
    publish_event("flow.execution.end.flow_chat", {
      flow_name: "TestFlow",
      action: "welcome"
    }, duration: 150.0)

    # Give time for event processing
    sleep 0.01

    metrics = @collector.snapshot
    assert_equal 1, metrics["flows.executed"]
    assert_equal 1, metrics["flows.by_name.TestFlow"]

    # Check timing metrics (allow some tolerance for timing precision)
    assert_in_delta 150.0, metrics["flows.execution_time.min"], 5.0
    assert_in_delta 150.0, metrics["flows.execution_time.max"], 5.0
    assert_in_delta 150.0, metrics["flows.execution_time.avg"], 5.0
  end

  def test_flow_execution_error_increments_error_counters
    publish_event("flow.execution.error.flow_chat", {
      flow_name: "TestFlow",
      error_class: "StandardError"
    })

    sleep 0.01

    metrics = @collector.snapshot
    assert_equal 1, metrics["flows.errors"]
    assert_equal 1, metrics["flows.errors.by_class.StandardError"]
    assert_equal 1, metrics["flows.errors.by_flow.TestFlow"]
  end

  def test_session_created_increments_session_counters
    publish_event("session.created.flow_chat", {
      session_id: "session_123",
      gateway: :whatsapp_cloud_api
    })

    sleep 0.01

    metrics = @collector.snapshot
    assert_equal 1, metrics["sessions.created"]
    assert_equal 1, metrics["sessions.created.by_gateway.whatsapp_cloud_api"]
  end

  def test_session_destroyed_increments_destroyed_counter
    publish_event("session.destroyed.flow_chat", {
      session_id: "session_123"
    })

    sleep 0.01

    metrics = @collector.snapshot
    assert_equal 1, metrics["sessions.destroyed"]
  end

  def test_session_cache_hit_and_miss_counters
    publish_event("session.cache.hit.flow_chat", {})
    publish_event("session.cache.miss.flow_chat", {})

    sleep 0.01

    metrics = @collector.snapshot
    assert_equal 1, metrics["sessions.cache.hits"]
    assert_equal 1, metrics["sessions.cache.misses"]
  end

  def test_whatsapp_message_events_increment_counters
    publish_event("message.received.flow_chat", {
      from: "+1234567890",
      message_type: "text",
      platform: :whatsapp
    })

    publish_event("message.sent.flow_chat", {
      to: "+1234567890",
      message_type: "text",
      platform: :whatsapp
    }, duration: 100.0)

    sleep 0.01

    metrics = @collector.snapshot
    assert_equal 1, metrics["whatsapp.messages.received"]
    assert_equal 1, metrics["whatsapp.messages.received.by_type.text"]
    assert_equal 1, metrics["whatsapp.messages.sent"]
    assert_equal 1, metrics["whatsapp.messages.sent.by_type.text"]

    # Check timing for sent messages (allow some tolerance for timing precision)
    assert_in_delta 100.0, metrics["whatsapp.api.response_time.avg"], 5.0
  end

  def test_whatsapp_api_request_success_and_failure
    publish_event("api.request.flow_chat", {
      success: true,
      endpoint: "/messages",
      platform: :whatsapp
    }, duration: 250.0)

    publish_event("api.request.flow_chat", {
      success: false,
      endpoint: "/messages",
      status: 400,
      platform: :whatsapp
    }, duration: 50.0)

    sleep 0.01

    metrics = @collector.snapshot
    assert_equal 1, metrics["whatsapp.api.requests.success"]
    assert_equal 1, metrics["whatsapp.api.requests.failure"]
    assert_equal 1, metrics["whatsapp.api.requests.failure.by_status.400"]

    # Check timing for API requests (allow some tolerance for timing precision)
    assert_in_delta 50.0, metrics["whatsapp.api.request_time.min"], 5.0
    assert_in_delta 250.0, metrics["whatsapp.api.request_time.max"], 5.0
    assert_in_delta 150.0, metrics["whatsapp.api.request_time.avg"], 5.0
  end

  def test_whatsapp_media_upload_success_and_failure
    publish_event("media.upload.flow_chat", {
      success: true,
      mime_type: "image/jpeg",
      size: 1024000,
      platform: :whatsapp
    }, duration: 2000.0)

    publish_event("media.upload.flow_chat", {
      success: false,
      mime_type: "video/mp4",
      error: "File too large",
      platform: :whatsapp
    }, duration: 100.0)

    sleep 0.01

    metrics = @collector.snapshot
    assert_equal 1, metrics["whatsapp.media.uploads.success"]
    assert_equal 1, metrics["whatsapp.media.uploads.failure"]

    # Check timing and size metrics (allow some tolerance for timing precision)
    assert_in_delta 100.0, metrics["whatsapp.media.upload_time.min"], 5.0
    assert_in_delta 2000.0, metrics["whatsapp.media.upload_time.max"], 10.0
    assert_equal 1024000, metrics["whatsapp.media.upload_size.avg"]  # Only successful uploads count for size
  end

  def test_ussd_message_events
    publish_event("message.received.flow_chat", {
      from: "+256700000000",
      message: "1",
      platform: :ussd
    })

    publish_event("message.sent.flow_chat", {
      to: "+256700000000",
      message_type: "prompt",
      platform: :ussd
    }, duration: 50.0)

    sleep 0.01

    metrics = @collector.snapshot
    assert_equal 1, metrics["ussd.messages.received"]
    assert_equal 1, metrics["ussd.messages.sent"]
    assert_equal 1, metrics["ussd.messages.sent.by_type.prompt"]
  end

  def test_ussd_pagination_events
    publish_event("pagination.triggered.flow_chat", {
      current_page: 2,
      total_pages: 5,
      content_length: 250,
      platform: :ussd
    })

    sleep 0.01

    metrics = @collector.snapshot
    assert_equal 1, metrics["ussd.pagination.triggered"]

    # Check content length metrics
    assert_equal 250, metrics["ussd.pagination.content_length.avg"]
  end

  def test_timing_metrics_calculation
    # Publish multiple events with different durations
    [100.0, 200.0, 300.0, 150.0, 250.0].each do |duration|
      publish_event("flow.execution.end.flow_chat", {
        flow_name: "TestFlow",
        action: "test"
      }, duration: duration)
    end

    sleep 0.01

    metrics = @collector.snapshot

    assert_equal 5, metrics["flows.executed"]
    assert_in_delta 100.0, metrics["flows.execution_time.min"], 5.0
    assert_in_delta 300.0, metrics["flows.execution_time.max"], 5.0
    assert_in_delta 200.0, metrics["flows.execution_time.avg"], 5.0  # (100+200+300+150+250)/5

    # Check percentiles (sorted: 100, 150, 200, 250, 300) - allow tolerance for timing
    assert_in_delta 200.0, metrics["flows.execution_time.p50"], 5.0  # median
    assert_in_delta 280.0, metrics["flows.execution_time.p95"], 15.0  # 95th percentile - more tolerance
    assert_in_delta 290.0, metrics["flows.execution_time.p99"], 15.0  # 99th percentile - more tolerance
  end

  def test_reset_clears_all_metrics
    publish_event("flow.execution.end.flow_chat", {
      flow_name: "TestFlow",
      action: "test"
    })

    sleep 0.01

    # Verify metrics exist
    metrics = @collector.snapshot
    refute_empty metrics

    # Reset and verify empty
    @collector.reset!
    metrics = @collector.snapshot
    assert_empty metrics
  end

  def test_get_category_returns_specific_metrics
    publish_event("flow.execution.end.flow_chat", {
      flow_name: "TestFlow",
      action: "test"
    })

    publish_event("session.created.flow_chat", {
      session_id: "session_123",
      gateway: :whatsapp_cloud_api
    })

    sleep 0.01

    # Get only flow metrics
    flow_metrics = @collector.get_category("flows")
    assert flow_metrics.keys.any? { |k| k.to_s.start_with?("flows.") }
    refute flow_metrics.keys.any? { |k| k.to_s.start_with?("sessions.") }

    # Get only session metrics
    session_metrics = @collector.get_category("sessions")
    assert session_metrics.keys.any? { |k| k.to_s.start_with?("sessions.") }
    refute session_metrics.keys.any? { |k| k.to_s.start_with?("flows.") }
  end

  def test_thread_safety
    threads = []

    # Start multiple threads publishing events
    10.times do |i|
      threads << Thread.new do
        10.times do |j|
          publish_event("flow.execution.end.flow_chat", {
            flow_name: "TestFlow#{i}",
            action: "test#{j}"
          }, duration: rand(100..500))
        end
      end
    end

    threads.each(&:join)
    sleep 0.1  # Give time for all events to process

    metrics = @collector.snapshot

    # Should have 100 total executions (10 threads * 10 events each)
    assert_equal 100, metrics["flows.executed"]

    # Should have metrics for each flow name
    10.times do |i|
      assert_equal 10, metrics["flows.by_name.TestFlow#{i}"]
    end
  end

  private

  def publish_event(name, payload, duration: 0.0)
    ActiveSupport::Notifications.instrument(name, payload) do
      sleep(duration / 1000.0) if duration > 0
    end
  end
end

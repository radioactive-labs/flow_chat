require "test_helper"
require "securerandom"

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

    metrics = @collector.snapshot
    assert_equal 1, metrics["flows.executed"]
    assert_equal 1, metrics["flows.by_name.TestFlow"]

    # The delta absorbs float noise in the monotonic clock arithmetic (~1e-8),
    # not scheduler jitter: the duration is stated, not slept.
    assert_in_delta 150.0, metrics["flows.execution_time.min"], 0.001
    assert_in_delta 150.0, metrics["flows.execution_time.max"], 0.001
    assert_in_delta 150.0, metrics["flows.execution_time.avg"], 0.001
  end

  def test_flow_execution_error_increments_error_counters
    publish_event("flow.execution.error.flow_chat", {
      flow_name: "TestFlow",
      error_class: "StandardError"
    })

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

    metrics = @collector.snapshot
    assert_equal 1, metrics["sessions.created"]
    assert_equal 1, metrics["sessions.created.by_gateway.whatsapp_cloud_api"]
  end

  def test_session_destroyed_increments_destroyed_counter
    publish_event("session.destroyed.flow_chat", {
      session_id: "session_123"
    })

    metrics = @collector.snapshot
    assert_equal 1, metrics["sessions.destroyed"]
  end

  def test_session_cache_hit_and_miss_counters
    publish_event("session.cache.hit.flow_chat", {})
    publish_event("session.cache.miss.flow_chat", {})

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

    metrics = @collector.snapshot
    assert_equal 1, metrics["whatsapp.messages.received"]
    assert_equal 1, metrics["whatsapp.messages.received.by_type.text"]
    assert_equal 1, metrics["whatsapp.messages.sent"]
    assert_equal 1, metrics["whatsapp.messages.sent.by_type.text"]

    assert_in_delta 100.0, metrics["whatsapp.api.response_time.avg"], 0.001
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

    metrics = @collector.snapshot
    assert_equal 1, metrics["whatsapp.api.requests.success"]
    assert_equal 1, metrics["whatsapp.api.requests.failure"]
    assert_equal 1, metrics["whatsapp.api.requests.failure.by_status.400"]

    assert_in_delta 50.0, metrics["whatsapp.api.request_time.min"], 0.001
    assert_in_delta 250.0, metrics["whatsapp.api.request_time.max"], 0.001
    assert_in_delta 150.0, metrics["whatsapp.api.request_time.avg"], 0.001
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

    metrics = @collector.snapshot
    assert_equal 1, metrics["whatsapp.media.uploads.success"]
    assert_equal 1, metrics["whatsapp.media.uploads.failure"]

    assert_in_delta 100.0, metrics["whatsapp.media.upload_time.min"], 0.001
    assert_in_delta 2000.0, metrics["whatsapp.media.upload_time.max"], 0.001
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

    metrics = @collector.snapshot

    assert_equal 5, metrics["flows.executed"]
    assert_in_delta 100.0, metrics["flows.execution_time.min"], 0.001
    assert_in_delta 300.0, metrics["flows.execution_time.max"], 0.001
    assert_in_delta 200.0, metrics["flows.execution_time.avg"], 0.001  # (100+200+300+150+250)/5

    # Percentiles over sorted [100, 150, 200, 250, 300], linearly interpolated
    # between neighbours as percentile/ does it: k = pct/100 * (n - 1), then
    # blend sorted[k.floor] and sorted[k.ceil] by the fractional part.
    #
    # The old expectations here were 280 and 290, which only passed because the
    # tolerance was 15. The implementation returns 290 and 298: for p95,
    # k = 3.8 gives 250*0.2 + 300*0.8 = 290.
    assert_in_delta 200.0, metrics["flows.execution_time.p50"], 0.001  # median, k = 2 exactly
    assert_in_delta 290.0, metrics["flows.execution_time.p95"], 0.001
    assert_in_delta 298.0, metrics["flows.execution_time.p99"], 0.001
  end

  def test_reset_clears_all_metrics
    publish_event("flow.execution.end.flow_chat", {
      flow_name: "TestFlow",
      action: "test"
    })

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

  # Publishes an event whose duration is exactly what the caller asked for.
  #
  # This used to instrument a block that really slept for the duration, so a
  # "250ms" event took 250ms of wall clock and recorded 250ms plus whatever
  # jitter the scheduler added. That made the file the slowest in the suite and
  # made every timing assertion flaky, which in turn forced tolerances so wide
  # (5 to 15ms) that they no longer pinned the arithmetic they exist to check.
  #
  # Note publish(name, start, finish, id, payload) does NOT work here: an
  # Event-object subscriber receives no duration from it. publish_event with a
  # constructed Event is the supported way to state one.
  def publish_event(name, payload, duration: 0.0)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    event = ActiveSupport::Notifications::Event.new(
      name, started, started + (duration / 1000.0), SecureRandom.hex(10), payload
    )
    ActiveSupport::Notifications.publish_event(event)
  end
end

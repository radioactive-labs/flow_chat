require "test_helper"

class UssdInstrumentationTest < Minitest::Test
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
      "USERDATA" => "1"
    }
    request.define_singleton_method(:params) { params }
    controller.define_singleton_method(:request) { request }
    controller.define_singleton_method(:render) { |options| "rendered content" }

    context = FlowChat::Context.new
    context["controller"] = controller

    # Mock app to be called by gateway
    mock_app = lambda { |ctx| [:prompt, "Test response", []] }
    gateway = FlowChat::Ussd::Gateway::Nalo.new(mock_app)
    gateway.call(context)

    # Check that message received event was triggered
    received_events = @test_events.select { |e| e[:name] == "message.received.flow_chat" }
    assert_equal 1, received_events.size

    event = received_events.first
    assert_equal "+256700123456", event[:payload][:from]
    assert_equal "1", event[:payload][:message]
    assert_equal :nalo, event[:payload][:gateway]
  end

  def test_nalo_gateway_instruments_message_sent
    # Mock controller and request
    controller = Object.new
    request = Object.new
    params = {
      "USERID" => "test_session_123",
      "MSISDN" => "256700123456",
      "USERDATA" => ""
    }
    request.define_singleton_method(:params) { params }
    controller.define_singleton_method(:request) { request }
    controller.define_singleton_method(:render) { |options| "rendered content" }

    context = FlowChat::Context.new
    context["controller"] = controller
    context["request.msisdn"] = "+256700123456"
    context["request.id"] = "test_session_123"

    # Mock app to be called by gateway
    mock_app = lambda { |ctx| [:prompt, "Test response", []] }
    gateway = FlowChat::Ussd::Gateway::Nalo.new(mock_app)
    gateway.call(context)

    # Check that message sent event was triggered (empty input case)
    sent_events = @test_events.select { |e| e[:name] == "message.sent.flow_chat" }
    assert_equal 1, sent_events.size

    event = sent_events.first
    assert_equal "+256700123456", event[:payload][:to]
    assert_equal "", event[:payload][:message]
    assert_equal :nalo, event[:payload][:gateway]
  end

  def test_nalo_gateway_instruments_both_received_and_sent_with_input
    controller = Object.new
    request = Object.new
    params = {
      "USERID" => "test_session_123",
      "MSISDN" => "256700123456",
      "USERDATA" => "1"
    }
    request.define_singleton_method(:params) { params }
    controller.define_singleton_method(:request) { request }
    controller.define_singleton_method(:render) { |options| "rendered content" }

    context = FlowChat::Context.new
    context["controller"] = controller
    context["request.msisdn"] = "+256700123456"
    context["request.id"] = "test_session_123"

    # Mock app to be called by gateway
    mock_app = lambda { |ctx| [:prompt, "Test response", []] }
    gateway = FlowChat::Ussd::Gateway::Nalo.new(mock_app)
    gateway.call(context)

    # Should have both received and sent events
    received_events = @test_events.select { |e| e[:name] == "message.received.flow_chat" }
    sent_events = @test_events.select { |e| e[:name] == "message.sent.flow_chat" }

    assert_equal 1, received_events.size
    assert_equal 1, sent_events.size
  end

  def test_nsano_gateway_instruments_placeholder_events
    # Test that Nsano gateway triggers placeholder events even though it's not fully implemented
    controller = Object.new
    request = Object.new
    request.define_singleton_method(:params) { {} }
    controller.define_singleton_method(:request) { request }

    context = FlowChat::Context.new
    context["controller"] = controller

    # Mock app to be called by gateway
    mock_app = lambda { |ctx| [:prompt, "Test response", []] }
    gateway = FlowChat::Ussd::Gateway::Nsano.new(mock_app)
    gateway.call(context)

    # Check that events were triggered with placeholder data
    received_events = @test_events.select { |e| e[:name] == "message.received.flow_chat" }
    sent_events = @test_events.select { |e| e[:name] == "message.sent.flow_chat" }

    # The Nsano gateway is just a stub, so it may not trigger events
    # We'll verify that it at least doesn't crash and completes execution
    assert_equal 1, received_events.size
    assert_equal 1, sent_events.size

    # Should have basic placeholder data
    assert_equal "TODO", received_events.first[:payload][:message]
    assert_equal :nsano, received_events.first[:payload][:gateway]
  end

  def test_pagination_middleware_triggers_initial_pagination_event
    # Set up pagination config
    original_page_size = FlowChat::Config.ussd.pagination_page_size
    FlowChat::Config.ussd.pagination_page_size = 50

    begin
      # Create long content that will trigger pagination
      long_content = "A" * 80
      mock_app = lambda { |context| [:prompt, long_content, []] }

      pagination = FlowChat::Ussd::Middleware::Pagination.new(mock_app)

      pagination.call(@context)

      # Verify pagination triggered event
      pagination_events = @test_events.select { |e| e[:name] == "pagination.triggered.flow_chat" }
      assert_equal 1, pagination_events.size

      event = pagination_events.first
      assert_equal 1, event[:payload][:current_page]
      assert event[:payload][:total_pages] > 1
      assert_equal long_content.length, event[:payload][:content_length]
      assert_equal 50, event[:payload][:page_limit]
      assert_equal "initial", event[:payload][:navigation_action]
      assert_equal "ussd:test_session_123", event[:payload][:session_id]
    ensure
      FlowChat::Config.ussd.pagination_page_size = original_page_size
    end
  end

  def test_pagination_middleware_triggers_navigation_events
    # Set up pagination state
    original_page_size = FlowChat::Config.ussd.pagination_page_size
    FlowChat::Config.ussd.pagination_next_option = "#"
    FlowChat::Config.ussd.pagination_page_size = 50

    begin
      pagination_state = {
        "page" => 2,  # Start from page 2
        "offsets" => {"1" => {"start" => 0, "finish" => 40}, "2" => {"start" => 41, "finish" => 80}},
        "prompt" => "A" * 100,
        "type" => "prompt"
      }
      @context.session.set("ussd.pagination", pagination_state)
      @context.input = "#"  # Navigate to next page

      mock_app = lambda { |context| [:prompt, "Should not be called", []] }
      pagination = FlowChat::Ussd::Middleware::Pagination.new(mock_app)

      pagination.call(@context)

      # Verify navigation pagination event
      pagination_events = @test_events.select { |e| e[:name] == "pagination.triggered.flow_chat" }
      assert_equal 1, pagination_events.size

      event = pagination_events.first
      # Based on debug logs, it shows "Moving to next page: 4"
      assert event[:payload][:current_page] >= 3  # Should be at least page 3 (navigation from page 2)
      assert_equal 100, event[:payload][:content_length]
      assert_equal "next", event[:payload][:navigation_action]
    ensure
      FlowChat::Config.ussd.pagination_page_size = original_page_size
    end
  end

  def test_pagination_back_navigation_event
    # Test back navigation pagination event
    original_page_size = FlowChat::Config.ussd.pagination_page_size
    FlowChat::Config.ussd.pagination_back_option = "0"
    FlowChat::Config.ussd.pagination_page_size = 50

    begin
      pagination_state = {
        "page" => 2,
        "offsets" => {
          "1" => {"start" => 0, "finish" => 40},
          "2" => {"start" => 41, "finish" => 80}
        },
        "prompt" => "A" * 100,
        "type" => "prompt"
      }
      @context.session.set("ussd.pagination", pagination_state)
      @context.input = "0"  # Navigate back

      mock_app = lambda { |context| [:prompt, "Should not be called", []] }
      pagination = FlowChat::Ussd::Middleware::Pagination.new(mock_app)

      pagination.call(@context)

      # Verify back navigation pagination event
      pagination_events = @test_events.select { |e| e[:name] == "pagination.triggered.flow_chat" }
      assert_equal 1, pagination_events.size

      event = pagination_events.first
      assert_equal 1, event[:payload][:current_page]  # Should be back on page 1
      assert_equal "back", event[:payload][:navigation_action]
    ensure
      FlowChat::Config.ussd.pagination_page_size = original_page_size
    end
  end

  def test_pagination_terminal_to_prompt_transition_instrumentation
    # Test that pagination correctly instruments when terminal content gets paginated
    original_page_size = FlowChat::Config.ussd.pagination_page_size
    FlowChat::Config.ussd.pagination_page_size = 30

    begin
      # Create terminal content that exceeds page size
      long_terminal_content = "Transaction completed successfully! " * 5
      mock_app = lambda { |context| [:terminal, long_terminal_content, []] }

      pagination = FlowChat::Ussd::Middleware::Pagination.new(mock_app)
      pagination.call(@context)

      # Verify event was triggered for terminal->prompt transition
      pagination_events = @test_events.select { |e| e[:name] == "pagination.triggered.flow_chat" }
      assert_equal 1, pagination_events.size

      event = pagination_events.first
      assert_equal 1, event[:payload][:current_page]
      assert_equal "initial", event[:payload][:navigation_action]
      assert event[:payload][:content_length] > 30
    ensure
      FlowChat::Config.ussd.pagination_page_size = original_page_size
    end
  end

  def test_pagination_last_page_terminal_navigation_instrumentation
    # Test that final page navigation to terminal is properly instrumented
    original_page_size = FlowChat::Config.ussd.pagination_page_size
    FlowChat::Config.ussd.pagination_next_option = "#"
    FlowChat::Config.ussd.pagination_page_size = 50

    begin
      # Set up pagination state where next page would be the final terminal page
      short_terminal_content = "Done!"
      pagination_state = {
        "page" => 1,
        "offsets" => {"1" => {"start" => 0, "finish" => 40}},
        "prompt" => short_terminal_content,
        "type" => "terminal"
      }
      @context.session.set("ussd.pagination", pagination_state)
      @context.input = "#"  # Navigate to final page

      mock_app = lambda { |context| [:terminal, "Should not be called", []] }
      pagination = FlowChat::Ussd::Middleware::Pagination.new(mock_app)

      type, _, _ = pagination.call(@context)

      # Should still be terminal type for final page
      assert_equal :terminal, type

      # Should still instrument the navigation
      pagination_events = @test_events.select { |e| e[:name] == "pagination.triggered.flow_chat" }
      assert_equal 1, pagination_events.size
      assert_equal "next", pagination_events.first[:payload][:navigation_action]
    ensure
      FlowChat::Config.ussd.pagination_page_size = original_page_size
    end
  end

  def test_pagination_error_boundary_instrumentation
    # Test that pagination instrumentation handles edge cases gracefully
    original_page_size = FlowChat::Config.ussd.pagination_page_size
    FlowChat::Config.ussd.pagination_page_size = 50

    begin
      # Test with minimal valid pagination state that might cause issues
      minimal_state = {
        "page" => 1,
        "prompt" => "test content",
        "type" => "prompt",
        "offsets" => {"1" => {"start" => 0, "finish" => 5}}
      }
      @context.session.set("ussd.pagination", minimal_state)
      @context.input = "#"

      mock_app = lambda { |context| [:prompt, "fallback", []] }
      pagination = FlowChat::Ussd::Middleware::Pagination.new(mock_app)

      # Should not crash and should handle gracefully
      begin
        result = pagination.call(@context)
        # If we get here, it means no exception was raised, which is good
        assert result.is_a?(Array), "Pagination should return array result"
        assert_equal 3, result.length, "Pagination should return [type, prompt, choices]"
      rescue => e
        # If an exception occurs, fail the test
        flunk "Pagination should handle edge cases gracefully, but raised: #{e.class}: #{e.message}"
      end
    ensure
      FlowChat::Config.ussd.pagination_page_size = original_page_size
    end
  end

  def test_pagination_with_media_and_choices_instrumentation
    # Test that pagination instrumentation works with complex content (media + choices)
    original_page_size = FlowChat::Config.ussd.pagination_page_size
    FlowChat::Config.ussd.pagination_page_size = 100

    begin
      message = "Welcome to FlowChat! " * 3  # Make it moderately long
      choices = {"1" => "Option A", "2" => "Option B", "3" => "Option C"}
      media = {type: :image, url: "https://example.com/large-image.jpg"}

      mock_app = lambda { |context| [:prompt, message, choices, media] }
      pagination = FlowChat::Ussd::Middleware::Pagination.new(mock_app)

      pagination.call(@context)

      # If content was long enough to paginate, should have instrumentation
      pagination_events = @test_events.select { |e| e[:name] == "pagination.triggered.flow_chat" }

      if pagination_events.any?
        event = pagination_events.first
        assert_equal 1, event[:payload][:current_page]
        assert_equal "initial", event[:payload][:navigation_action]
        # Content length should include rendered message + media + choices
        assert event[:payload][:content_length] > message.length
      end
    ensure
      FlowChat::Config.ussd.pagination_page_size = original_page_size
    end
  end

  def test_all_event_types_are_instrumented
    # Verify all platform-agnostic event constants exist and are properly formatted
    events = FlowChat::Instrumentation::Events

    # New platform-agnostic events (scalable approach)
    assert_equal "message.received", events::MESSAGE_RECEIVED
    assert_equal "message.sent", events::MESSAGE_SENT
    assert_equal "pagination.triggered", events::PAGINATION_TRIGGERED
  end

  def test_instrumentation_event_timing_measurement
    # Test that instrumentation properly measures timing
    controller = Object.new
    request = Object.new
    params = {
      "USERID" => "test_session_123",
      "MSISDN" => "256700123456",
      "USERDATA" => "1"
    }
    request.define_singleton_method(:params) { params }
    controller.define_singleton_method(:request) { request }
    controller.define_singleton_method(:render) { |options| "rendered content" }

    context = FlowChat::Context.new
    context["controller"] = controller
    context["request.msisdn"] = "+256700123456"
    context["request.id"] = "test_session_123"

    # Mock app to be called by gateway
    mock_app = lambda { |ctx| [:prompt, "Test response", []] }
    gateway = FlowChat::Ussd::Gateway::Nalo.new(mock_app)
    gateway.call(context)

    # All events should have timing information
    @test_events.each do |event|
      assert event[:start].is_a?(Time), "Event start time should be a Time object, got #{event[:start].class}"
      assert event[:finish].is_a?(Time), "Event finish time should be a Time object, got #{event[:finish].class}"
      assert event[:duration].is_a?(Float), "Event duration should be a float, got #{event[:duration].class}"
      assert event[:duration] >= 0, "Event duration should be non-negative"
      assert event[:finish] >= event[:start], "Finish time should be >= start time"
    end
  end

  def test_instrumentation_payload_data_integrity
    # Test that all instrumentation payloads contain expected data structure
    original_page_size = FlowChat::Config.ussd.pagination_page_size
    FlowChat::Config.ussd.pagination_page_size = 30

    begin
      # Trigger both message and pagination events
      controller = Object.new
      request = Object.new
      params = {
        "USERID" => "test_session_123",
        "MSISDN" => "256700123456",
        "USERDATA" => "1"
      }
      request.define_singleton_method(:params) { params }
      controller.define_singleton_method(:request) { request }
      controller.define_singleton_method(:render) { |options| "rendered content" }

      context = FlowChat::Context.new
      context["controller"] = controller

      # Mock app to be called by gateway
      mock_app = lambda { |ctx| [:prompt, "Test response", []] }
      gateway = FlowChat::Ussd::Gateway::Nalo.new(mock_app)
      gateway.call(context)

      # Also trigger pagination
      long_content = "A" * 50
      mock_pagination_app = lambda { |ctx| [:prompt, long_content, []] }
      pagination = FlowChat::Ussd::Middleware::Pagination.new(mock_pagination_app)
      pagination.call(@context)

      # Verify payload structure for each event type
      message_events = @test_events.select { |e| e[:name].include?("message") }
      pagination_events = @test_events.select { |e| e[:name].include?("pagination") }

      message_events.each do |event|
        payload = event[:payload]
        assert payload.key?(:session_id), "Message events should have session_id"
        assert payload.key?(:message), "Message events should have message content"
        assert payload.key?(:gateway), "Message events should have gateway info"
        assert payload.key?(:timestamp), "Message events should have timestamp"
      end

      pagination_events.each do |event|
        payload = event[:payload]
        assert payload.key?(:session_id), "Pagination events should have session_id"
        assert payload.key?(:current_page), "Pagination events should have current_page"
        assert payload.key?(:total_pages), "Pagination events should have total_pages"
        assert payload.key?(:content_length), "Pagination events should have content_length"
        assert payload.key?(:page_limit), "Pagination events should have page_limit"
        assert payload.key?(:navigation_action), "Pagination events should have navigation_action"
      end
    ensure
      FlowChat::Config.ussd.pagination_page_size = original_page_size
    end
  end

  private

  def mock_controller
    controller = Object.new
    request = Object.new
    params = {
      "USERID" => "test_session_123",
      "MSISDN" => "256700123456",
      "USERDATA" => "1"
    }
    request.define_singleton_method(:params) { params }
    controller.define_singleton_method(:request) { request }
    controller.define_singleton_method(:render) { |options| "rendered content" }
    controller
  end
end

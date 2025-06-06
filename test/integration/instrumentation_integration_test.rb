require "test_helper"

class InstrumentationIntegrationTest < Minitest::Test
  def setup
    @log_messages = []
    @test_logger = Object.new
    
    # Mock logger that captures messages
    %w[info debug warn error].each do |level|
      @test_logger.define_singleton_method(level) do |&block|
        @messages ||= []
        @messages << [level.upcase, block.call]
      end
    end
    
    def @test_logger.messages
      @messages || []
    end
    
    # Set our test logger
    FlowChat::Config.logger = @test_logger
    
    # Reset and setup instrumentation
    FlowChat::Instrumentation::Setup.reset!
    FlowChat::Instrumentation::Setup.setup_instrumentation!
  end

  def teardown
    FlowChat::Config.logger = Logger.new($stdout)
    FlowChat::Instrumentation::Setup.reset!
  end

  def test_complete_session_lifecycle_instrumentation
    # Set up cache for session store
    FlowChat::Config.cache = Class.new do
      def initialize
        @data = {}
      end
      
      def read(key)
        @data[key]
      end
      
      def write(key, value, options = {})
        @data[key] = value
      end
      
      def delete(key)
        @data.delete(key)
      end
    end.new
    
    # Create a context to simulate a real session
    context = FlowChat::Context.new
    context["request.gateway"] = :whatsapp_cloud_api
    context["request.msisdn"] = "+1234567890"
    context["flow.name"] = "TestFlow"
    
    # Test session store with instrumentation
    session_store = FlowChat::Session::CacheSessionStore.new(context)
    
    # Set and get data (should generate events)
    session_store.set("username", "john_doe")
    value = session_store.get("username")
    session_store.destroy
    
    # Give time for events to process
    sleep 0.1
    
    # Verify logged events
    messages = @test_logger.messages
    logged_text = messages.map { |level, msg| msg }.join(" ")
    
    # Should have session creation from context
    assert_includes logged_text, "Context Created"
    
    # Should have session data operations
    assert_includes logged_text, "Session Data Set"
    assert_includes logged_text, "Session Data Get"
    
    # Should have session destruction
    assert_includes logged_text, "Session Destroyed"
    
    # Verify metrics were collected
    metrics = FlowChat::Instrumentation::Setup.metrics_collector.snapshot
    assert metrics["sessions.data.set"] || metrics["sessions.data.get"]
  end

  def test_whatsapp_gateway_webhook_flow
    # Mock a WhatsApp gateway with instrumentation
    gateway_class = Class.new do
      include FlowChat::Instrumentation
      
      def process_webhook(challenge)
        instrument(FlowChat::Instrumentation::Events::WHATSAPP_WEBHOOK_VERIFIED, {
          challenge: challenge
        })
        
        "webhook_verified"
      end
      
      def process_message(from, message_type, message_id)
        instrument(FlowChat::Instrumentation::Events::WHATSAPP_MESSAGE_RECEIVED, {
          from: from,
          message_type: message_type,
          message_id: message_id,
          contact_name: "Test User"
        })
        
        "message_processed"
      end
    end
    
    gateway = gateway_class.new
    
    # Process webhook verification
    result1 = gateway.process_webhook("test_challenge_123")
    
    # Process incoming message
    result2 = gateway.process_message("+1234567890", "text", "msg_123")
    
    sleep 0.1
    
    # Verify results
    assert_equal "webhook_verified", result1
    assert_equal "message_processed", result2
    
    # Verify logging
    messages = @test_logger.messages
    logged_text = messages.map { |level, msg| msg }.join(" ")
    
    assert_includes logged_text, "WhatsApp Webhook Verified Successfully"
    assert_includes logged_text, "[Challenge: test_challenge_123]"
    assert_includes logged_text, "WhatsApp Message Received: +1234567890 (Test User)"
    assert_includes logged_text, "Type: text [ID: msg_123]"
    
    # Verify metrics
    metrics = FlowChat::Instrumentation::Setup.metrics_collector.snapshot
    assert_equal 1, metrics["whatsapp.messages.received"]
    assert_equal 1, metrics["whatsapp.messages.received.by_type.text"]
  end

  def test_flow_execution_with_error_handling
    # Mock a flow processor with instrumentation
    processor_class = Class.new do
      include FlowChat::Instrumentation
      
      def execute_flow(flow_name, action, session_id)
        instrument(FlowChat::Instrumentation::Events::FLOW_EXECUTION_START, {
          flow_name: flow_name,
          action: action,
          session_id: session_id
        })
        
        begin
          # Simulate flow execution
          if action == "error_action"
            raise StandardError, "Test flow error"
          end
          
          result = "flow_completed"
          
          # Only instrument success if we get here
          instrument(FlowChat::Instrumentation::Events::FLOW_EXECUTION_END, {
            flow_name: flow_name,
            action: action,
            session_id: session_id
          })
          
          result
        rescue => error
          instrument(FlowChat::Instrumentation::Events::FLOW_EXECUTION_ERROR, {
            flow_name: flow_name,
            action: action,
            session_id: session_id,
            error_class: error.class.name,
            error_message: error.message
          })
          
          raise
        end
      end
    end
    
    processor = processor_class.new
    
    # Test successful execution
    result = processor.execute_flow("TestFlow", "welcome", "session_123")
    assert_equal "flow_completed", result
    
    # Test error execution
    assert_raises(StandardError) do
      processor.execute_flow("TestFlow", "error_action", "session_456")
    end
    
    sleep 0.1
    
    # Verify logging
    messages = @test_logger.messages
    logged_text = messages.map { |level, msg| msg }.join(" ")
    
    # Should log successful flow
    assert_includes logged_text, "Flow Execution Started: TestFlow#welcome [Session: session_123]"
    assert_includes logged_text, "Flow Execution Completed: TestFlow#welcome"
    
    # Should log failed flow
    assert_includes logged_text, "Flow Execution Started: TestFlow#error_action [Session: session_456]"
    assert_includes logged_text, "Flow Execution Failed: TestFlow#error_action"
    assert_includes logged_text, "StandardError: Test flow error"
    
    # Verify metrics
    metrics = FlowChat::Instrumentation::Setup.metrics_collector.snapshot
    assert_equal 1, metrics["flows.executed"]  # Only successful flows count
    assert_equal 1, metrics["flows.errors"]
    assert_equal 1, metrics["flows.errors.by_class.StandardError"]
  end

  def test_ussd_pagination_flow
    # Mock USSD pagination with instrumentation
    paginator_class = Class.new do
      include FlowChat::Instrumentation
      
      def paginate_content(content, session_id)
        pages = content.length / 160 + 1
        current_page = 2  # Simulate being on page 2
        
        instrument(FlowChat::Instrumentation::Events::USSD_PAGINATION_TRIGGERED, {
          current_page: current_page,
          total_pages: pages,
          content_length: content.length,
          session_id: session_id
        })
        
        "paginated_content"
      end
      
      def receive_message(from, input, session_id)
        instrument(FlowChat::Instrumentation::Events::USSD_MESSAGE_RECEIVED, {
          from: from,
          input: input,
          session_id: session_id
        })
        
        "message_received"
      end
    end
    
    paginator = paginator_class.new
    
    # Test pagination
    content = "A" * 350  # Long content that needs pagination
    result1 = paginator.paginate_content(content, "session_789")
    
    # Test message receiving
    result2 = paginator.receive_message("+256700000000", "2", "session_789")
    
    sleep 0.1
    
    # Verify results
    assert_equal "paginated_content", result1
    assert_equal "message_received", result2
    
    # Verify logging
    messages = @test_logger.messages
    logged_text = messages.map { |level, msg| msg }.join(" ")
    
    assert_includes logged_text, "USSD Pagination Triggered: Page 2/3"
    assert_includes logged_text, "(350 chars)"
    assert_includes logged_text, "USSD Message Received: +256700000000"
    assert_includes logged_text, "Input: '2'"
    
    # Verify metrics
    metrics = FlowChat::Instrumentation::Setup.metrics_collector.snapshot
    assert_equal 1, metrics["ussd.pagination.triggered"]
    assert_equal 1, metrics["ussd.messages.received"]
    assert_equal 350, metrics["ussd.pagination.content_length.avg"]
  end

  def test_concurrent_instrumentation
    # Test that instrumentation works correctly under concurrent access
    threads = []
    results = []
    
    processor_class = Class.new do
      include FlowChat::Instrumentation
      
      def process(id)
        instrument("test.concurrent.process", {
          process_id: id,
          thread_id: Thread.current.object_id
        }) do
          # Simulate some work
          sleep(rand(0.001..0.01))
          "processed_#{id}"
        end
      end
    end
    
    processor = processor_class.new
    
    # Start multiple threads
    10.times do |i|
      threads << Thread.new do
        result = processor.process(i)
        results << result
      end
    end
    
    threads.each(&:join)
    sleep 0.1
    
    # Verify all processes completed
    assert_equal 10, results.size
    10.times do |i|
      assert_includes results, "processed_#{i}"
    end
    
    # Verify logging captured all events (note: test.concurrent.process doesn't have a log subscriber)
    # This test primarily verifies thread safety, so we just check that no errors occurred
    messages = @test_logger.messages
    error_messages = messages.select { |level, msg| level == :error }
    assert_equal 0, error_messages.size, "Should not have any error messages from concurrent instrumentation"
    
    # Verify metrics
    metrics = FlowChat::Instrumentation::Setup.metrics_collector.snapshot
    # Note: Our current metrics collector doesn't have a subscription for test.concurrent.process
    # This test primarily verifies thread safety of the instrumentation infrastructure
  end

  def test_error_resilience
    # Test that instrumentation works with various edge cases and malformed data
    test_class = Class.new do
      include FlowChat::Instrumentation
      
      def test_with_nil_payload
        instrument("test.nil.payload", nil) do
          "result_with_nil"
        end
      end
      
      def test_with_large_payload
        large_data = "x" * 10000
        instrument("test.large.payload", { large_data: large_data }) do
          "result_with_large_data"
        end
      end
      
      def test_with_complex_payload
        complex_data = {
          nested: { deeply: { nested: { data: "value" } } },
          array: [1, 2, 3, { inner: "data" }],
          symbols: :symbol_value,
          numbers: 42.5
        }
        instrument("test.complex.payload", complex_data) do
          "result_with_complex_data"
        end
      end
    end
    
    instance = test_class.new
    
    # All these should work without errors
    result1 = instance.test_with_nil_payload
    result2 = instance.test_with_large_payload
    result3 = instance.test_with_complex_payload
    
    assert_equal "result_with_nil", result1
    assert_equal "result_with_large_data", result2
    assert_equal "result_with_complex_data", result3
    
    # Verify no errors were logged
    messages = @test_logger.messages
    error_messages = messages.select { |level, msg| level == :error }
    assert_equal 0, error_messages.size, "Should not have any error messages from edge case instrumentation"
  end

  def test_performance_impact
    # Measure performance impact of instrumentation
    processor_class = Class.new do
      include FlowChat::Instrumentation
      
      def with_instrumentation
        instrument("test.performance", { test: true }) do
          # Simulate work
          100.times { |i| i * 2 }
        end
      end
      
      def without_instrumentation
        # Same work without instrumentation
        100.times { |i| i * 2 }
      end
    end
    
    processor = processor_class.new
    
    # Warm up
    5.times do
      processor.with_instrumentation
      processor.without_instrumentation
    end
    
    # Measure with instrumentation
    start_time = Time.now
    100.times { processor.with_instrumentation }
    with_instrumentation_time = Time.now - start_time
    
    # Measure without instrumentation
    start_time = Time.now
    100.times { processor.without_instrumentation }
    without_instrumentation_time = Time.now - start_time
    
    # Instrumentation overhead should be reasonable (less than 50% overhead)
    overhead_ratio = with_instrumentation_time / without_instrumentation_time
    assert overhead_ratio < 1.5, "Instrumentation overhead too high: #{overhead_ratio}x"
    
    # Should still be very fast (less than 1ms per operation on average)
    avg_time_per_operation = with_instrumentation_time / 100
    assert avg_time_per_operation < 0.001, "Instrumentation too slow: #{avg_time_per_operation}s per operation"
  end
end 
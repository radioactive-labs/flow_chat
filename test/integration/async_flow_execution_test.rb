require "test_helper"

class AsyncFlowExecutionTest < Minitest::Test
  class TestAsyncJob < FlowChat::AsyncJob
    cattr_accessor :last_execution

    def execute(controller, **job_params)
      # Store execution details for verification
      self.class.last_execution = {
        controller: controller,
        job_params: job_params,
        executed: true
      }

      # Build and run processor like a real implementation would
      processor = FlowChat::Processor.new(controller) do |config|
        config.use_gateway(TestGateway)
        config.use_session_store(MockSessionStore)
      end

      processor.run(TestFlow, :start)
    end
  end

  class TestGateway
    include FlowChat::GatewayAsyncSupport

    def initialize(app)
      @app = app
    end

    def call(context)
      @context = context
      @controller = context.controller
      request = @controller.request

      # Set up basic context
      context["request.id"] = request.params["session_id"] || "test_session"
      context["request.user_id"] = request.params["user_id"] || "test_user"
      context["request.platform"] = :test
      context["request.gateway"] = :test_gateway
      context.input = request.params["input"] || ""

      # Check if we should enqueue async
      if should_enqueue_async?
        enqueue_async_job
        return @controller.render json: {status: "processing"}
      else
        # Process inline
        @app.call(context)
        @controller.render json: {status: "ok"}
      end
    end
  end

  class TestFlow
    def initialize(app)
      @app = app
    end

    def start
      @app.say "Flow executed successfully"
    end
  end

  class MockSessionStore
    def initialize(session_options = nil)
      @options = session_options
    end

    def load(_session_id, _context)
      {}
    end

    def save(_session_id, _session_data, _context)
    end

    def destroy
      # No-op for mock
    end
  end

  def setup
    TestAsyncJob.last_execution = nil
  end

  def test_inline_execution_when_async_not_configured
    controller = create_mock_controller

    processor = FlowChat::Processor.new(controller) do |config|
      config.use_gateway(TestGateway)
      config.use_session_store(MockSessionStore)
    end

    processor.run(TestFlow, :start)

    # Should process inline, not enqueue job
    assert_nil TestAsyncJob.last_execution
  end

  def test_async_enqueue_when_configured_with_webhook_controller
    controller = create_mock_controller

    processor = FlowChat::Processor.new(controller) do |config|
      config.use_gateway(TestGateway)
      config.use_session_store(MockSessionStore)
      config.use_async(TestAsyncJob)
    end

    # Mock the job class to verify it gets called
    job_enqueued = false
    TestAsyncJob.stub(:perform_later, ->(args) { job_enqueued = true; args }) do
      processor.run(TestFlow, :start)
    end

    # Should enqueue job
    assert job_enqueued
  end

  def test_inline_execution_when_in_background_mode
    # Create a BackgroundController (simulating background job execution)
    request_data = {
      params: {"session_id" => "test_123", "input" => "Hello"},
      method: "POST",
      headers: {}
    }
    background_controller = FlowChat::BackgroundController.new(request_data)

    processor = FlowChat::Processor.new(background_controller) do |config|
      config.use_gateway(TestGateway)
      config.use_session_store(MockSessionStore)
      config.use_async(TestAsyncJob)
    end

    # Even with async configured, should execute inline in background mode
    processor.run(TestFlow, :start)

    # Should NOT enqueue another job
    assert_nil TestAsyncJob.last_execution
  end

  def test_full_async_cycle_from_webhook_to_background_execution
    # Step 1: Webhook receives request with async configured
    webhook_controller = create_mock_controller
    webhook_processor = FlowChat::Processor.new(webhook_controller) do |config|
      config.use_gateway(TestGateway)
      config.use_session_store(MockSessionStore)
      config.use_async(TestAsyncJob)
    end

    # Capture the request data that would be serialized
    captured_request_context = nil

    TestAsyncJob.stub(:perform_later, ->(args) {
      captured_request_context = args[:request_context]
    }) do
      webhook_processor.run(TestFlow, :start)
    end

    # Verify job would be enqueued with correct data
    refute_nil captured_request_context
    assert_equal "POST", captured_request_context[:method]
    assert captured_request_context[:params].is_a?(Hash)

    # Step 2: Background job processes the request
    job = TestAsyncJob.new
    job.perform(
      request_context: captured_request_context
    )

    # Verify background execution happened
    refute_nil TestAsyncJob.last_execution
    assert TestAsyncJob.last_execution[:executed]
    assert_instance_of FlowChat::BackgroundController, TestAsyncJob.last_execution[:controller]
  end

  def test_gateway_without_async_support_never_enqueues
    # Create a gateway that doesn't support async
    no_async_gateway_class = Class.new(TestGateway) do
      def async_supported?
        false
      end
    end

    controller = create_mock_controller
    processor = FlowChat::Processor.new(controller) do |config|
      config.use_gateway(no_async_gateway_class)
      config.use_session_store(MockSessionStore)
      config.use_async(TestAsyncJob)
    end

    # Even with async configured, should not enqueue
    job_enqueued = false
    TestAsyncJob.stub(:perform_later, ->(_args) { job_enqueued = true }) do
      processor.run(TestFlow, :start)
    end

    refute job_enqueued
  end

  def test_request_context_serialization_preserves_data
    controller = create_mock_controller(
      params: {"session_id" => "sess_456", "user_id" => "user_789", "input" => "Test message"},
      method: "POST",
      headers: {"Content-Type" => "application/json", "User-Agent" => "TestClient/1.0"}
    )

    processor = FlowChat::Processor.new(controller) do |config|
      config.use_gateway(TestGateway)
      config.use_session_store(MockSessionStore)
      config.use_async(TestAsyncJob)
    end

    captured_context = nil
    TestAsyncJob.stub(:perform_later, ->(args) { captured_context = args[:request_context] }) do
      processor.run(TestFlow, :start)
    end

    # Verify all important data is preserved
    assert_equal "sess_456", captured_context[:params]["session_id"]
    assert_equal "user_789", captured_context[:params]["user_id"]
    assert_equal "Test message", captured_context[:params]["input"]
    assert_equal "POST", captured_context[:method]
    assert_equal "application/json", captured_context[:headers]["Content-Type"]
    assert_equal "TestClient/1.0", captured_context[:headers]["User-Agent"]
  end

  private

  def create_mock_controller(params: {}, method: "POST", headers: {})
    controller = Object.new
    request = Object.new

    default_params = {"session_id" => "test_session", "input" => "Hello"}
    default_headers = {"Content-Type" => "application/json"}

    final_params = default_params.merge(params).with_indifferent_access
    final_headers = default_headers.merge(headers)

    request.define_singleton_method(:params) { final_params }
    request.define_singleton_method(:method) { method }
    request.define_singleton_method(:headers) { final_headers }

    controller.define_singleton_method(:request) { request }
    controller.define_singleton_method(:render) { |args| nil }

    controller
  end
end

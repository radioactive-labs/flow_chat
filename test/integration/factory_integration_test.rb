require "test_helper"

class FactoryIntegrationTest < Minitest::Test
  class TestAsyncJob < FlowChat::AsyncJob
    cattr_accessor :last_job_params

    def execute(controller, **job_params)
      self.class.last_job_params = job_params
      # No-op for testing
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

      context["request.id"] = "test_session"
      context["request.platform"] = :test
      context["request.gateway"] = :test
      context.input = ""

      if should_enqueue_async?
        enqueue_async_job
        @controller.render json: {status: "processing"}
      else
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
    FlowChat::Factory.clear!
    TestAsyncJob.last_job_params = nil
  end

  def teardown
    FlowChat::Factory.clear!
  end

  def test_factory_executes_flow_successfully
    FlowChat::Factory.register(:test) do |controller|
      processor = FlowChat::Processor.new(controller) do |config|
        config.use_gateway(TestGateway)
        config.use_session_store(MockSessionStore)
      end
      processor.run(TestFlow, :start)
    end

    controller = create_mock_controller

    # Should execute without error
    FlowChat::Factory.execute(:test, controller: controller)
  end

  def test_factory_with_async_enabled_enqueues_job
    FlowChat::Factory.register(:test) do |controller|
      processor = FlowChat::Processor.new(controller) do |config|
        config.use_gateway(TestGateway)
        config.use_session_store(MockSessionStore)
        config.use_async(TestAsyncJob)
      end
      processor.run(TestFlow, :start)
    end

    controller = create_mock_controller
    job_enqueued = false

    TestAsyncJob.stub(:perform_later, ->(args) { job_enqueued = true }) do
      FlowChat::Factory.execute(:test, controller: controller)
    end

    assert job_enqueued
  end

  def test_factory_with_async_in_background_processes_inline
    FlowChat::Factory.register(:test) do |controller|
      processor = FlowChat::Processor.new(controller) do |config|
        config.use_gateway(TestGateway)
        config.use_session_store(MockSessionStore)
        config.use_async(TestAsyncJob)
      end
      processor.run(TestFlow, :start)
    end

    # Create background controller
    bg_controller = FlowChat::BackgroundController.new({
      params: {"input" => "test"},
      method: "POST",
      headers: {}
    })

    job_enqueued = false
    TestAsyncJob.stub(:perform_later, ->(args) { job_enqueued = true }) do
      FlowChat::Factory.execute(:test, controller: bg_controller)
    end

    # Should NOT enqueue another job in background
    refute job_enqueued
  end

  def test_factory_with_job_params_passes_them_to_job
    FlowChat::Factory.register(:test) do |controller|
      processor = FlowChat::Processor.new(controller) do |config|
        config.use_gateway(TestGateway)
        config.use_session_store(MockSessionStore)
        config.use_async(TestAsyncJob, deployment_id: 123, flow_name: "TestFlow")
      end
      processor.run(TestFlow, :start)
    end

    controller = create_mock_controller
    captured_params = nil

    TestAsyncJob.stub(:perform_later, ->(args) {
      captured_params = args
    }) do
      FlowChat::Factory.execute(:test, controller: controller)
    end

    assert_equal 123, captured_params[:deployment_id]
    assert_equal "TestFlow", captured_params[:flow_name]
  end

  def test_factory_can_be_reused_across_multiple_calls
    call_count = 0

    FlowChat::Factory.register(:test) do |controller|
      call_count += 1
      processor = FlowChat::Processor.new(controller) do |config|
        config.use_gateway(TestGateway)
        config.use_session_store(MockSessionStore)
      end
      processor.run(TestFlow, :start)
    end

    controller1 = create_mock_controller
    controller2 = create_mock_controller

    FlowChat::Factory.execute(:test, controller: controller1)
    FlowChat::Factory.execute(:test, controller: controller2)

    assert_equal 2, call_count
  end

  def test_factory_raises_error_for_unregistered_factory
    controller = create_mock_controller

    error = assert_raises(FlowChat::Factory::FactoryNotFoundError) do
      FlowChat::Factory.execute(:unknown, controller: controller)
    end

    assert_match(/not registered/, error.message)
    assert_match(/unknown/, error.message)
  end

  def test_multiple_factories_can_be_registered
    FlowChat::Factory.register(:whatsapp) do |controller|
      processor = FlowChat::Processor.new(controller) do |config|
        config.use_gateway(TestGateway)
        config.use_session_store(MockSessionStore)
      end
      processor.run(TestFlow, :start)
    end

    FlowChat::Factory.register(:intercom) do |controller|
      processor = FlowChat::Processor.new(controller) do |config|
        config.use_gateway(TestGateway)
        config.use_session_store(MockSessionStore)
      end
      processor.run(TestFlow, :start)
    end

    assert FlowChat::Factory.registered?(:whatsapp)
    assert FlowChat::Factory.registered?(:intercom)

    # Both should execute without error
    FlowChat::Factory.execute(:whatsapp, controller: create_mock_controller)
    FlowChat::Factory.execute(:intercom, controller: create_mock_controller)
  end

  def test_use_async_without_job_class_uses_generic_async_job
    FlowChat::Factory.register(:test) do |controller|
      processor = FlowChat::Processor.new(controller) do |config|
        config.use_gateway(TestGateway)
        config.use_session_store(MockSessionStore)
      end
      processor.run(TestFlow, :start)
    end

    controller = create_mock_controller

    processor = FlowChat::Processor.new(controller) do |config|
      config.use_gateway(TestGateway)
      config.use_session_store(MockSessionStore)
      config.use_async(factory: :test)  # No job class - uses GenericAsyncJob
    end

    # Should use GenericAsyncJob
    assert_equal FlowChat::GenericAsyncJob, processor.async_job_class
    assert_equal :test, processor.async_job_params[:factory]
  end

  def test_generic_async_job_enqueues_with_factory_param
    FlowChat::Factory.register(:test) do |controller|
      processor = FlowChat::Processor.new(controller) do |config|
        config.use_gateway(TestGateway)
        config.use_session_store(MockSessionStore)
      end
      processor.run(TestFlow, :start)
    end

    controller = create_mock_controller

    processor = FlowChat::Processor.new(controller) do |config|
      config.use_gateway(TestGateway)
      config.use_session_store(MockSessionStore)
      config.use_async(factory: :test)
    end

    captured_params = nil
    FlowChat::GenericAsyncJob.stub(:perform_later, ->(args) {
      captured_params = args
    }) do
      processor.run(TestFlow, :start)
    end

    assert_equal :test, captured_params[:factory]
    refute_nil captured_params[:request_context]
  end

  def test_generic_async_job_executes_factory_in_background
    factory_executed = false

    FlowChat::Factory.register(:test) do |controller|
      factory_executed = true
      processor = FlowChat::Processor.new(controller) do |config|
        config.use_gateway(TestGateway)
        config.use_session_store(MockSessionStore)
      end
      processor.run(TestFlow, :start)
    end

    request_data = {
      params: {"input" => "test"},
      method: "POST",
      headers: {}
    }

    job = FlowChat::GenericAsyncJob.new
    job.perform(request_context: request_data, factory: :test)

    assert factory_executed
  end

  private

  def create_mock_controller
    controller = Object.new
    request = Object.new

    request.define_singleton_method(:params) { {"input" => "test"}.with_indifferent_access }
    request.define_singleton_method(:method) { "POST" }
    request.define_singleton_method(:headers) { {"Content-Type" => "application/json"} }

    controller.define_singleton_method(:request) { request }
    controller.define_singleton_method(:render) { |args| nil }

    controller
  end
end

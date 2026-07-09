require "test_helper"

class ProcessorAsyncTest < Minitest::Test
  class TestAsyncJob < FlowChat::AsyncJob
    def execute(controller, **job_params)
      # No-op for testing
    end
  end

  def setup
    @controller = create_mock_controller
  end

  def test_processor_initializes_with_nil_async_job_class
    processor = FlowChat::Processor.new(@controller)

    assert_nil processor.async_job_class
  end

  def test_async_enabled_returns_false_by_default
    processor = FlowChat::Processor.new(@controller)

    refute processor.async_enabled?
  end

  def test_use_async_sets_job_class
    processor = FlowChat::Processor.new(@controller)

    result = processor.use_async(TestAsyncJob)

    assert_equal TestAsyncJob, processor.async_job_class
    assert_equal processor, result # Should return self for chaining
  end

  def test_async_enabled_returns_true_when_job_class_is_set
    processor = FlowChat::Processor.new(@controller)
    processor.use_async(TestAsyncJob)

    assert processor.async_enabled?
  end

  def test_use_async_can_be_chained_with_other_config_methods
    processor = FlowChat::Processor.new(@controller) do |config|
      config.use_async(TestAsyncJob)
        .use_session_config(boundaries: [:flow])
    end

    assert processor.async_enabled?
    assert_equal TestAsyncJob, processor.async_job_class
  end

  def test_processor_stores_itself_in_context_on_run
    app = create_test_flow
    processor = FlowChat::Processor.new(@controller) do |config|
      config.use_gateway(TestGateway)
      config.use_session_store(MockSessionStore)
    end

    # Run will set processor in context
    processor.run(app, :start)

    # Access the context that was created
    context = processor.context
    assert_equal processor, context["processor"]
  end

  def test_use_async_accepts_job_params
    processor = FlowChat::Processor.new(@controller)

    result = processor.use_async(TestAsyncJob, deployment_id: 123, flow_name: "TestFlow")

    assert_equal TestAsyncJob, processor.async_job_class
    assert_equal 123, processor.async_job_params[:deployment_id]
    assert_equal "TestFlow", processor.async_job_params[:flow_name]
    assert_equal processor, result # Should return self for chaining
  end

  def test_async_job_params_defaults_to_empty_hash
    processor = FlowChat::Processor.new(@controller)

    assert_equal({}, processor.async_job_params)
  end

  def test_use_async_without_params_sets_empty_hash
    processor = FlowChat::Processor.new(@controller)
    processor.use_async(TestAsyncJob)

    assert_equal({}, processor.async_job_params)
  end

  def test_use_async_without_job_class_requires_factory_param
    processor = FlowChat::Processor.new(@controller)

    error = assert_raises(ArgumentError) do
      processor.use_async
    end

    assert_match(/factory.*required/, error.message)
  end

  def test_use_async_without_job_class_uses_generic_async_job
    processor = FlowChat::Processor.new(@controller)

    result = processor.use_async(factory: :whatsapp)

    assert_equal FlowChat::GenericAsyncJob, processor.async_job_class
    assert_equal :whatsapp, processor.async_job_params[:factory]
    assert_equal processor, result # Should return self for chaining
  end

  def test_use_async_without_job_class_accepts_additional_params
    processor = FlowChat::Processor.new(@controller)

    processor.use_async(factory: :whatsapp, deployment_id: 123)

    assert_equal FlowChat::GenericAsyncJob, processor.async_job_class
    assert_equal :whatsapp, processor.async_job_params[:factory]
    assert_equal 123, processor.async_job_params[:deployment_id]
  end

  private

  def create_mock_controller
    controller = Object.new
    request = Object.new
    request.define_singleton_method(:params) { {}.with_indifferent_access }
    request.define_singleton_method(:post?) { true }
    controller.define_singleton_method(:request) { request }
    controller.define_singleton_method(:head) { |status| nil }
    controller
  end

  def create_test_flow
    Class.new do
      def self.name
        "TestFlow"
      end

      def initialize(app)
        @app = app
      end

      def start
        @app.say "Hello"
      end
    end
  end

  class TestGateway
    def initialize(app)
      @app = app
    end

    def call(context)
      context["request.id"] = "test_123"
      context["request.platform"] = :test
      context["request.gateway"] = :test
      context.input = ""
      @app.call(context)
      context.controller.head :ok
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
end

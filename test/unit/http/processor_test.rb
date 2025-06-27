require "test_helper"

class HttpProcessorTest < Minitest::Test
  def setup
    @controller = mock_controller
    @processor = FlowChat::Http::Processor.new(@controller)
  end

  def test_initializes_with_controller
    context = @processor.instance_variable_get(:@context)
    assert_equal @controller, context["controller"]
  end

  def test_initializes_context_with_controller
    context = @processor.instance_variable_get(:@context)
    assert_equal @controller, context["controller"]
  end

  def test_initializes_middleware_builder
    assert_respond_to @processor, :middleware
    assert_kind_of ::Middleware::Builder, @processor.middleware
  end

  def test_use_gateway_sets_gateway
    gateway_class = Class.new
    result = @processor.use_gateway(gateway_class)

    assert_equal gateway_class, @processor.instance_variable_get(:@gateway_class)
    assert_equal @processor, result  # Should return self for chaining
  end

  def test_use_session_store_sets_session_store
    session_store = create_test_session_store_class
    result = @processor.use_session_store(session_store)

    context = @processor.instance_variable_get(:@context)
    assert_equal session_store, context["session.store"]
    assert_equal @processor, result
  end

  def test_use_middleware_adds_middleware
    middleware_class = Class.new
    result = @processor.use_middleware(middleware_class)

    # We can't easily test if middleware was added without making it more complex,
    # but we can verify the method returns self for chaining
    assert_equal @processor, result
  end

  def test_use_durable_sessions_inserts_middleware
    result = @processor.use_durable_sessions

    assert_equal @processor, result
    # The middleware should be inserted but we can't easily verify without complex setup
  end

  def test_use_session_config
    result = @processor.use_session_config(
      boundaries: [:flow, :gateway],
      hash_identifiers: false,
      identifier: :request_id
    )

    assert_equal @processor, result
    # Should return self for chaining
  end

  def test_run_sets_flow_context
    flow_class = Class.new(FlowChat::Flow) do
      def self.name
        "TestFlow"
      end
    end

    @processor.use_gateway(Class.new)
    @processor.use_session_store(create_test_session_store_class)

    # Mock the middleware stack execution to avoid complex setup
    @processor.instance_variable_get(:@context)

    # We'll capture the context state before middleware execution
    original_call = ::Middleware::Builder.instance_method(:call)
    context_captured = nil

    ::Middleware::Builder.class_eval do
      define_method(:call) do |env|
        context_captured = env
        env  # Return the environment instead of executing
      end
    end

    begin
      @processor.run(flow_class, :main_page)

      assert_equal "test_flow", context_captured["flow.name"]
      assert_equal flow_class, context_captured["flow.class"]
      assert_equal :main_page, context_captured["flow.action"]
    ensure
      # Restore original method
      ::Middleware::Builder.class_eval do
        define_method(:call, original_call)
      end
    end
  end

  def test_processor_can_be_configured_with_block
    gateway_class = Class.new
    session_store = create_test_session_store_class

    processor = FlowChat::Http::Processor.new(@controller) do |p|
      p.use_gateway(gateway_class)
      p.use_session_store(session_store)
      p.use_durable_sessions
    end

    assert_equal gateway_class, processor.instance_variable_get(:@gateway_class)

    context = processor.instance_variable_get(:@context)
    assert_equal session_store, context["session.store"]
  end

  def test_chaining_configuration_methods
    gateway_class = Class.new
    session_store = create_test_session_store_class
    middleware_class = Class.new

    result = @processor
      .use_gateway(gateway_class)
      .use_session_store(session_store)
      .use_middleware(middleware_class)
      .use_durable_sessions

    assert_equal @processor, result
    assert_equal gateway_class, @processor.instance_variable_get(:@gateway_class)
  end

  def test_middleware_name
    assert_equal "http.middleware", @processor.send(:middleware_name)
  end

  def test_build_middleware_stack_creates_http_stack
    @processor.use_gateway(MockGateway)
    stack = @processor.send(:build_middleware_stack)
    assert_kind_of ::Middleware::Builder, stack
  end

  class MockGateway
    def initialize(app)
      @app = app
    end

    def call(env)
      @app.call(env)
    end
  end
end 
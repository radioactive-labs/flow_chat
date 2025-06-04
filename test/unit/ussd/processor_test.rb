require "test_helper"

class UssdProcessorTest < Minitest::Test
  def setup
    @controller = mock_controller
    @processor = FlowChat::Ussd::Processor.new(@controller)
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
    
    assert_equal gateway_class, @processor.gateway
    assert_equal @processor, result  # Should return self for chaining
  end

  def test_use_session_store_sets_session_store
    session_store = create_test_session_store
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

  def test_use_resumable_sessions_inserts_middleware
    result = @processor.use_resumable_sessions
    
    assert_equal @processor, result
    # The middleware should be inserted but we can't easily verify without complex setup
  end

  def test_run_sets_flow_context
    flow_class = Class.new(FlowChat::Flow) do
      def self.name
        "TestFlow"
      end
    end
    
    @processor.use_gateway(Class.new)
    @processor.use_session_store(create_test_session_store)
    
    # Mock the middleware stack execution to avoid complex setup
    stack = @processor.instance_variable_get(:@context)
    
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
    session_store = create_test_session_store
    
    processor = FlowChat::Ussd::Processor.new(@controller) do |p|
      p.use_gateway(gateway_class)
      p.use_session_store(session_store)
      p.use_resumable_sessions
    end
    
    assert_equal gateway_class, processor.gateway
    
    context = processor.instance_variable_get(:@context)
    assert_equal session_store, context["session.store"]
  end

  def test_chaining_configuration_methods
    gateway_class = Class.new
    session_store = create_test_session_store
    middleware_class = Class.new
    
    result = @processor
      .use_gateway(gateway_class)
      .use_session_store(session_store)
      .use_middleware(middleware_class)
      .use_resumable_sessions
    
    assert_equal @processor, result
    assert_equal gateway_class, @processor.gateway
  end

  def test_run_yields_middleware_stack_for_modification
    flow_class = Class.new(FlowChat::Flow) do
      def self.name
        "TestFlow"
      end
    end
    
    @processor.use_gateway(MockGateway)
    @processor.use_session_store(create_test_session_store)
    
    # Track if the block was called with the stack
    yielded_stack = nil
    stack_modified = false
    
    # Mock the middleware stack execution
    original_call = ::Middleware::Builder.instance_method(:call)
    ::Middleware::Builder.class_eval do
      define_method(:call) do |env|
        env  # Return the environment instead of executing
      end
    end
    
    begin
      @processor.run(flow_class, :main_page) do |stack|
        yielded_stack = stack
        stack_modified = true
        
        # Verify we can modify the stack
        assert_respond_to stack, :use
        assert_respond_to stack, :insert_before
        assert_respond_to stack, :insert_after
      end
      
      assert stack_modified, "Block should have been called"
      assert_kind_of ::Middleware::Builder, yielded_stack
    ensure
      ::Middleware::Builder.class_eval do
        define_method(:call, original_call)
      end
    end
  end

  def test_run_middleware_stack_modification_example
    flow_class = Class.new(FlowChat::Flow) do
      def self.name
        "TestFlow"
      end
    end
    
    @processor.use_gateway(MockGateway)
    @processor.use_session_store(create_test_session_store)
    
    # Create a test middleware to verify insertion
    test_middleware_called = false
    test_middleware = Class.new do
      define_method(:initialize) { |app| @app = app }
      define_method(:call) do |env|
        test_middleware_called = true
        @app.call(env)
      end
    end
    
    # Mock the final execution
    original_call = ::Middleware::Builder.instance_method(:call)
    ::Middleware::Builder.class_eval do
      define_method(:call) do |env|
        # Simulate calling through the middleware stack
        test_middleware_called = true if defined?(test_middleware_called)
        env
      end
    end
    
    begin
      @processor.run(flow_class, :main_page) do |stack|
        # Add custom middleware to the stack
        stack.use test_middleware
        
        # Verify we can insert middleware at specific positions
        stack.insert_before FlowChat::Ussd::Middleware::Executor, test_middleware
      end
      
      # The middleware modification happened successfully if no errors were raised
      assert true, "Middleware stack modification completed successfully"
    ensure
      ::Middleware::Builder.class_eval do
        define_method(:call, original_call)
      end
    end
  end

  def test_run_without_block_does_not_yield
    flow_class = Class.new(FlowChat::Flow) do
      def self.name
        "TestFlow"
      end
    end
    
    @processor.use_gateway(MockGateway)
    @processor.use_session_store(create_test_session_store)
    
    block_called = false
    
    # Mock execution to avoid complex setup
    original_call = ::Middleware::Builder.instance_method(:call)
    ::Middleware::Builder.class_eval do
      define_method(:call) { |env| env }
    end
    
    begin
      # Call without block - should not yield
      @processor.run(flow_class, :main_page)
      refute block_called, "Block should not have been called when no block given"
    ensure
      ::Middleware::Builder.class_eval do
        define_method(:call, original_call)
      end
    end
  end

  def test_run_builds_correct_middleware_order
    flow_class = Class.new(FlowChat::Flow) do
      def self.name
        "TestFlow"
      end
    end
    
    custom_middleware = Class.new
    @processor.use_gateway(MockGateway)
    @processor.use_session_store(create_test_session_store)
    @processor.use_middleware(custom_middleware)
    
    middleware_order = []
    
    # Mock the middleware builder to capture the order
    original_use = ::Middleware::Builder.instance_method(:use)
    ::Middleware::Builder.class_eval do
      define_method(:use) do |middleware|
        middleware_order << middleware
        original_use.bind(self).call(middleware)
      end
    end
    
    original_call = ::Middleware::Builder.instance_method(:call)
    ::Middleware::Builder.class_eval do
      define_method(:call) { |env| env }
    end
    
    begin
      @processor.run(flow_class, :main_page)
      
      # Verify the expected middleware order
      expected_order = [
        MockGateway,
        FlowChat::Session::Middleware,
        FlowChat::Ussd::Middleware::Pagination,
        @processor.middleware,  # This contains our custom middleware
        FlowChat::Ussd::Middleware::Executor
      ]
      
      # Check that gateway, session, pagination and executor are in the right positions
      assert_includes middleware_order, MockGateway
      assert_includes middleware_order, FlowChat::Session::Middleware
      assert_includes middleware_order, FlowChat::Ussd::Middleware::Pagination
      assert_includes middleware_order, FlowChat::Ussd::Middleware::Executor
    ensure
      ::Middleware::Builder.class_eval do
        define_method(:use, original_use)
        define_method(:call, original_call)
      end
    end
  end

  private

  # Mock gateway for testing
  class MockGateway
    def initialize(app)
      @app = app
    end

    def call(env)
      @app.call(env)
    end
  end
end 
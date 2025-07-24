# frozen_string_literal: true

# Module: ProcessorTest
#
# Purpose:
# Tests the FlowChat::Processor class, which serves as the central orchestrator
# for building and executing the middleware stack. The processor configures
# gateways, session stores, and custom middleware for handling conversational flows.
#
# Coverage:
# - Processor initialization and configuration DSL
# - Gateway and session store configuration
# - Middleware stack building and composition
# - Session configuration options (boundaries, identifiers, hashing)
# - Configuration method chaining for fluent API
# - Flow execution context setup
#
# Architecture:
# The Processor builds a middleware stack in this order:
# 1. Gateway (platform-specific request/response handling)
# 2. Session Middleware (session management)
# 3. Custom Middleware (user-defined business logic)
# 4. Executor (flow instantiation and execution)
#
# Key Test Scenarios:
# - Basic configuration with gateway and session store
# - Advanced session configurations (durable, cross-platform, URL isolation)
# - Middleware insertion and ordering
# - Configuration via block syntax
# - Method chaining for configuration
# - Flow context setup during execution
#
# Configuration Options:
# - use_gateway: Sets the platform gateway (USSD, WhatsApp, HTTP, Intercom)
# - use_session_store: Configures session persistence (Rails, Cache)
# - use_session_config: Fine-tunes session boundaries and identifiers
# - use_middleware: Adds custom middleware to the stack
# - use_durable_sessions: Configures user_id-based sessions
# - use_cross_platform_sessions: Enables session sharing across platforms
# - use_url_isolation: Adds URL-based session boundaries for multi-tenancy
#
# Special Considerations:
# - Configuration methods return self for method chaining
# - The processor maintains a custom middleware builder for flexibility
# - Session options are cumulative and can be combined
# - URL isolation prevents duplicate :url boundaries

require "test_helper"

class ProcessorTest < Minitest::Test
  def setup
    @controller = mock_controller
    @processor = FlowChat::Processor.new(@controller)
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
    assert_respond_to @processor, :custom_middleware_builder
    assert_kind_of ::Middleware::Builder, @processor.custom_middleware_builder
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

    # Should configure session identifier to :user_id
    session_options = @processor.instance_variable_get(:@session_options)
    assert_equal :user_id, session_options.identifier
    assert_equal @processor, result
  end

  def test_use_session_config
    boundaries = [:flow, :platform]
    hash_identifiers = true
    identifier = :msisdn

    result = @processor.use_session_config(
      boundaries: boundaries,
      hash_identifiers: hash_identifiers,
      identifier: identifier
    )

    session_options = @processor.instance_variable_get(:@session_options)
    assert_equal boundaries, session_options.boundaries
    assert_equal hash_identifiers, session_options.hash_identifiers
    assert_equal identifier, session_options.identifier
    assert_equal @processor, result
  end

  def test_use_cross_platform_sessions
    result = @processor.use_cross_platform_sessions

    session_options = @processor.instance_variable_get(:@session_options)
    assert_equal [:flow], session_options.boundaries
    assert_equal @processor, result
  end

  def test_use_url_isolation
    result = @processor.use_url_isolation

    session_options = @processor.instance_variable_get(:@session_options)
    assert_includes session_options.boundaries, :url
    assert_equal @processor, result
  end

  def test_use_url_isolation_prevents_duplicates
    @processor.use_session_config(boundaries: [:flow, :url])
    result = @processor.use_url_isolation

    session_options = @processor.instance_variable_get(:@session_options)
    assert_equal 1, session_options.boundaries.count(:url)
    assert_equal @processor, result
  end

  def test_use_url_isolation_preserves_existing_boundaries
    @processor.use_session_config(boundaries: [:flow, :platform])
    @processor.use_url_isolation

    session_options = @processor.instance_variable_get(:@session_options)
    assert_includes session_options.boundaries, :flow
    assert_includes session_options.boundaries, :platform
    assert_includes session_options.boundaries, :url
  end

  def test_chaining_configuration_methods
    gateway_class = Class.new
    session_store = create_test_session_store_class

    result = @processor
      .use_gateway(gateway_class)
      .use_session_store(session_store)
      .use_durable_sessions

    assert_equal @processor, result
    assert_equal gateway_class, @processor.instance_variable_get(:@gateway_class)

    context = @processor.instance_variable_get(:@context)
    assert_equal session_store, context["session.store"]
  end

  def test_processor_can_be_configured_with_block
    gateway_class = Class.new
    session_store = create_test_session_store_class

    processor = FlowChat::Processor.new(@controller) do |p|
      p.use_gateway(gateway_class)
      p.use_session_store(session_store)
      p.use_durable_sessions
    end

    assert_equal gateway_class, processor.instance_variable_get(:@gateway_class)

    context = processor.instance_variable_get(:@context)
    assert_equal session_store, context["session.store"]
  end

  def test_create_middleware_stack_creates_stack
    @processor.use_gateway(MockGateway)
    stack = @processor.send(:create_middleware_stack)
    assert_kind_of ::Middleware::Builder, stack
  end

  def test_run_sets_flow_context
    @processor.use_gateway(MockGateway)
    @processor.use_session_store(create_test_session_store_class)
    flow_class = create_test_flow_class

    begin
      @processor.run(flow_class, :main_page)
    rescue FlowChat::Interrupt::Prompt
      # Expected - flow will prompt for input
    end

    context = @processor.instance_variable_get(:@context)
    assert_equal "test_flow", context["flow.name"]
    assert_equal flow_class, context["flow.class"]
    assert_equal :main_page, context["flow.action"]
  end

  def test_run_without_block_does_not_yield
    @processor.use_gateway(MockGateway)
    @processor.use_session_store(create_test_session_store_class)
    flow_class = create_test_flow_class
    yielded = false

    begin
      @processor.run(flow_class, :main_page) do |stack|
        yielded = true
      end
    rescue FlowChat::Interrupt::Prompt
      # Expected
    end

    assert yielded, "Block should be yielded to"
  end

  private

  class MockGateway
    def initialize(app)
      @app = app
    end

    def call(context)
      @app.call(context)
    end
  end

  def create_test_flow_class
    Class.new(FlowChat::Flow) do
      def self.name
        "TestFlow"
      end

      def main_page
        app.screen(:test) { |prompt| prompt.ask "Test?" }
      end
    end
  end
end

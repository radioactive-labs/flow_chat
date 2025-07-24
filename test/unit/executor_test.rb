# frozen_string_literal: true

# Module: ExecutorTest
#
# Purpose:
# Tests the FlowChat::Executor class, which is responsible for instantiating and
# executing flow instances, handling flow control interrupts, and managing the
# flow lifecycle within the middleware stack.
#
# Coverage:
# - Flow instantiation and execution
# - Interrupt handling (Prompt, Terminate, RestartFlow)
# - Session cleanup on termination
# - Error propagation and handling
# - Platform-specific app building
# - Edge case handling for flows without proper interrupts
#
# Architecture:
# The Executor sits at the end of the middleware stack and:
# 1. Creates platform-specific App instances
# 2. Instantiates the flow class with the app
# 3. Executes the specified flow action
# 4. Catches and handles flow control interrupts
# 5. Returns appropriate response tuples
#
# Interrupt Types:
# - Prompt: Normal flow continuation, returns [:prompt, message, choices, options]
# - Terminate: Ends the session, returns [:terminal, message, nil, nil]
# - RestartFlow: Restarts from beginning, recursively calls the flow
#
# Key Test Scenarios:
# - Basic flow execution with prompt interrupt
# - Session termination and cleanup
# - Flow restart handling
# - Error propagation for non-interrupt exceptions
# - Handling flows that don't raise interrupts (edge case)
#
# Response Format:
# All responses follow the tuple format: [type, message, choices, options]
# - type: :prompt or :terminal
# - message: The text to display
# - choices: Hash of available choices (can be nil)
# - options: Additional rendering options (can be nil)
#
# Special Considerations:
# - The executor expects flows to raise interrupts for control flow
# - Flows that complete without interrupts trigger "Unexpected end of flow"
# - The executor is stateless and relies on context for all state
# - Platform-specific behavior is delegated to App subclasses

require "test_helper"

class ExecutorTest < Minitest::Test
  def setup
    @context = FlowChat::Context.new
    @context["controller"] = mock_controller
    @context.session = create_test_session_store
    @mock_app = lambda { |ctx| [:prompt, "Test response", nil, nil] }
    @executor = FlowChat::Executor.new(@mock_app)
  end

  def test_is_flow_chat_executor
    assert_kind_of FlowChat::Executor, @executor
  end

  def test_initializes_with_app
    assert_equal @mock_app, @executor.instance_variable_get(:@app)
  end

  def test_log_prefix
    assert_equal "Executor", @executor.send(:log_prefix)
  end

  def test_build_platform_app_returns_base_app
    app = @executor.send(:build_platform_app, @context)
    assert_kind_of FlowChat::App, app
    assert_equal @context, app.context
  end

  def test_call_executes_flow
    flow_class = create_test_flow_class
    @context["flow.class"] = flow_class
    @context["flow.action"] = :main_page

    # Override the flow method to return a prompt
    flow_class.define_method(:main_page) do
      raise FlowChat::Interrupt::Prompt.new("Test prompt")
    end

    result = @executor.call(@context)
    assert_equal [:prompt, "Test prompt", nil, nil], result
  end

  def test_call_handles_terminate_interrupt
    flow_class = create_test_flow_class
    @context["flow.class"] = flow_class
    @context["flow.action"] = :main_page
    @context["session.id"] = "test_session"

    # Mock session destroy
    @context.session.define_singleton_method(:destroy) {}

    # Override the flow method to return a terminate
    flow_class.define_method(:main_page) do
      raise FlowChat::Interrupt::Terminate.new("Test message")
    end

    result = @executor.call(@context)
    assert_equal [:terminal, "Test message", nil, nil], result
  end

  def test_call_handles_restart_flow_interrupt
    flow_class = create_test_flow_class
    @context["flow.class"] = flow_class
    @context["flow.action"] = :main_page

    call_count = 0
    # Override the flow method with restart logic
    flow_class.define_method(:main_page) do
      call_count += 1
      if call_count == 1
        raise FlowChat::Interrupt::RestartFlow.new
      else
        raise FlowChat::Interrupt::Prompt.new("After restart")
      end
    end

    result = @executor.call(@context)
    assert_equal [:prompt, "After restart", nil, nil], result
  end

  def test_call_propagates_other_errors
    flow_class = create_test_flow_class
    @context["flow.class"] = flow_class
    @context["flow.action"] = :main_page

    # Override the flow method to raise a StandardError
    flow_class.define_method(:main_page) do
      raise StandardError, "Test error"
    end

    assert_raises(StandardError) do
      @executor.call(@context)
    end
  end

  def test_call_handles_flow_without_interrupt
    flow_class = create_test_flow_class
    @context["flow.class"] = flow_class
    @context["flow.action"] = :main_page

    # Override the flow method to do nothing (invalid flow)
    flow_class.define_method(:main_page) do
      # Do nothing - should trigger "Unexpected end of flow"
    end

    result = @executor.call(@context)
    assert_equal [:terminal, "Unexpected end of flow.", nil, nil], result
  end

  private

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

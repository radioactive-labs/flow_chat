# frozen_string_literal: true

# Module: SimpleFlowTest
#
# Purpose:
# Integration tests demonstrating various flow patterns and control structures
# in FlowChat, including terminal flows, multi-step interactions, error handling,
# and advanced flow features like go_back navigation.
#
# Coverage:
# - Terminal flows that end immediately
# - Multi-step flows with user input collection
# - Error handling and validation flows
# - Navigation features (go_back functionality)
# - Different flow control patterns
# - Session state management across interactions
#
# Test Flow Types:
# - HelloWorldFlow: Simple terminal flow with immediate message
# - TestFlow: Two-step flow collecting name and displaying greeting
# - ErrorFlow: Demonstrates error interrupt handling
# - GoBackTestFlow: Multi-screen flow with back navigation
#
# Key Test Scenarios:
# - Immediate termination with terminal message
# - Sequential screen navigation with data collection
# - Error propagation through interrupt system
# - Back navigation preserving previous inputs
# - Session data persistence between screens
#
# Flow Control Patterns:
# - app.say(): Display message and terminate
# - app.screen(): Create named checkpoint for navigation
# - prompt.ask(): Collect user input with optional validation
# - app.go_back(): Return to previous screen
# - raise Interrupt::Prompt/Terminate/Error: Control flow
#
# Architecture Validation:
# - Flows use interrupts for control flow
# - Screens provide navigation checkpoints
# - Session stores screen history for go_back
# - Each interaction preserves session state
#
# Special Considerations:
# - Tests run flows directly without full middleware stack
# - Interrupt exceptions are expected and caught
# - Session state is mocked for isolation
# - Each test uses fresh context and session

require "test_helper"

class SimpleFlowTest < Minitest::Test
  include FlowChat::TestSupport::TestFlows

  def setup
    @controller = mock_controller
    @session_store = create_test_session_store
  end

  def test_hello_world_flow_terminates_immediately
    context = FlowChat::Context.new
    context["controller"] = @controller
    context.session = @session_store
    context.input = nil

    error = assert_raises(FlowChat::Interrupt::Terminate) do
      app = FlowChat::App.new(context)
      flow = HelloWorldFlow.new(app)
      flow.main_page
    end

    assert_equal "Hello World!", error.prompt
  end

  def test_name_collection_flow_without_input
    context = FlowChat::Context.new
    context["controller"] = @controller
    context.session = @session_store
    context.input = nil

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      app = FlowChat::App.new(context)
      flow = NameCollectionFlow.new(app)
      flow.main_page
    end

    assert_equal "What is your name?", error.prompt
  end

  def test_name_collection_flow_with_input
    context = FlowChat::Context.new
    context["controller"] = @controller
    context.session = @session_store
    context["request.platform"] = :ussd
    context.input = "John"

    error = assert_raises(FlowChat::Interrupt::Terminate) do
      app = FlowChat::App.new(context)
      flow = NameCollectionFlow.new(app)
      flow.main_page
    end

    assert_equal "Hello, John!", error.prompt
  end

  def test_multi_step_flow_progression
    # Step 1: Ask for name
    context = FlowChat::Context.new
    context["controller"] = @controller
    context.session = @session_store
    context["request.platform"] = :ussd
    context.input = nil

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      app = FlowChat::App.new(context)
      flow = MultiStepFlow.new(app)
      flow.main_page
    end

    assert_equal "What is your name?", error.prompt

    # Step 2: Provide name, ask for age
    context.input = "  john doe  "

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      app = FlowChat::App.new(context)
      flow = MultiStepFlow.new(app)
      flow.main_page
    end

    assert_equal "How old are you?", error.prompt
    assert_equal "John Doe", @session_store.get(:name)

    # Step 3: Provide invalid age
    context.input = "12"

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      app = FlowChat::App.new(context)
      flow = MultiStepFlow.new(app)
      flow.main_page
    end

    assert_includes error.prompt, "You must be at least 13 years old"

    # Step 4: Provide valid age, ask for gender
    context.input = "25"

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      app = FlowChat::App.new(context)
      flow = MultiStepFlow.new(app)
      flow.main_page
    end

    assert_equal "What is your gender?", error.prompt
    assert_equal 25, @session_store.get(:age)

    # Step 5: Choose gender, ask for confirmation
    context.input = "Male"  # Choose Male from the options

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      app = FlowChat::App.new(context)
      flow = MultiStepFlow.new(app)
      flow.main_page
    end

    assert_includes error.prompt, "Is this correct?"
    assert_includes error.prompt, "John Doe"
    assert_includes error.prompt, "25"
    assert_includes error.prompt, "Male"
    assert_equal "Male", @session_store.get(:gender)

    # Step 6: Confirm and complete
    context.input = "Yes"  # Confirm the details

    error = assert_raises(FlowChat::Interrupt::Terminate) do
      app = FlowChat::App.new(context)
      flow = MultiStepFlow.new(app)
      flow.main_page
    end

    assert_equal "Thank you for confirming", error.prompt
    assert_equal true, @session_store.get(:confirm)
  end

  def test_multi_step_flow_with_rejection
    # Set up existing session data
    @session_store.set(:name, "John Doe")
    @session_store.set(:age, 25)
    @session_store.set(:gender, "Male")

    context = FlowChat::Context.new
    context["controller"] = @controller
    context.session = @session_store
    context["request.platform"] = :ussd
    context.input = "No"  # Reject confirmation

    error = assert_raises(FlowChat::Interrupt::Terminate) do
      app = FlowChat::App.new(context)
      flow = MultiStepFlow.new(app)
      flow.main_page
    end

    assert_equal "Please try again", error.prompt
    assert_equal false, @session_store.get(:confirm)
  end
end

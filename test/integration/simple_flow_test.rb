require "test_helper"

class SimpleFlowTest < Minitest::Test
  # Test flow classes
  class HelloWorldFlow < FlowChat::Flow
    def main_page
      app.say "Hello World!"
    end
  end

  class NameCollectionFlow < FlowChat::Flow
    def main_page
      name = app.screen(:name) { |prompt| prompt.ask "What is your name?" }
      app.say "Hello, #{name}!"
    end
  end

  class MultiStepFlow < FlowChat::Flow
    def main_page
      name = app.screen(:name) { |prompt|
        prompt.ask "What is your name?", transform: ->(input) { input.strip.titleize }
      }

      age = app.screen(:age) do |prompt|
        prompt.ask "How old are you?",
          convert: ->(input) { input.to_i },
          validate: ->(input) { "You must be at least 13 years old" unless input >= 13 }
      end

      gender = app.screen(:gender) { |prompt| prompt.select "What is your gender?", ["Male", "Female"] }

      confirm = app.screen(:confirm) do |prompt|
        prompt.yes?("Is this correct?\n\nName: #{name}\nAge: #{age}\nGender: #{gender}")
      end

      app.say confirm ? "Thank you for confirming" : "Please try again"
    end
  end

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
      app = FlowChat::Ussd::App.new(context)
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
      app = FlowChat::Ussd::App.new(context)
      flow = NameCollectionFlow.new(app)
      flow.main_page
    end

    assert_equal "What is your name?", error.prompt
  end

  def test_name_collection_flow_with_input
    context = FlowChat::Context.new
    context["controller"] = @controller
    context.session = @session_store
    context.input = "John"

    error = assert_raises(FlowChat::Interrupt::Terminate) do
      app = FlowChat::Ussd::App.new(context)
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
    context.input = nil

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      app = FlowChat::Ussd::App.new(context)
      flow = MultiStepFlow.new(app)
      flow.main_page
    end

    assert_equal "What is your name?", error.prompt

    # Step 2: Provide name, ask for age
    context.input = "  john doe  "

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      app = FlowChat::Ussd::App.new(context)
      flow = MultiStepFlow.new(app)
      flow.main_page
    end

    assert_equal "How old are you?", error.prompt
    assert_equal "John Doe", @session_store.get(:name)

    # Step 3: Provide invalid age
    context.input = "12"

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      app = FlowChat::Ussd::App.new(context)
      flow = MultiStepFlow.new(app)
      flow.main_page
    end

    assert_includes error.prompt, "You must be at least 13 years old"

    # Step 4: Provide valid age, ask for gender
    context.input = "25"

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      app = FlowChat::Ussd::App.new(context)
      flow = MultiStepFlow.new(app)
      flow.main_page
    end

    assert_equal "What is your gender?", error.prompt
    assert_equal 25, @session_store.get(:age)

    # Step 5: Choose gender, ask for confirmation
    context.input = "1"  # Male

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      app = FlowChat::Ussd::App.new(context)
      flow = MultiStepFlow.new(app)
      flow.main_page
    end

    assert_includes error.prompt, "Is this correct?"
    assert_includes error.prompt, "John Doe"
    assert_includes error.prompt, "25"
    assert_includes error.prompt, "Male"
    assert_equal "Male", @session_store.get(:gender)

    # Step 6: Confirm and complete
    context.input = "1"  # Yes

    error = assert_raises(FlowChat::Interrupt::Terminate) do
      app = FlowChat::Ussd::App.new(context)
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
    context.input = "2"  # No - reject confirmation

    error = assert_raises(FlowChat::Interrupt::Terminate) do
      app = FlowChat::Ussd::App.new(context)
      flow = MultiStepFlow.new(app)
      flow.main_page
    end

    assert_equal "Please try again", error.prompt
    assert_equal false, @session_store.get(:confirm)
  end
end

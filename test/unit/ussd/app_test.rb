require "test_helper"

class UssdAppTest < Minitest::Test
  def setup
    @context = FlowChat::Context.new
    @context.session = create_test_session_store
    @context.input = "test_input"
    @app = FlowChat::Ussd::App.new(@context)
  end

  def test_initializes_with_context
    assert_equal @context, @app.context
    assert_equal @context.session, @app.session
    assert_equal "test_input", @app.input
  end

  def test_navigation_stack_starts_empty
    assert_empty @app.navigation_stack
  end

  def test_screen_requires_block
    assert_raises(ArgumentError, "a block is expected") do
      @app.screen(:test_screen)
    end
  end

  def test_screen_prevents_duplicate_screens
    @app.screen(:duplicate_screen) { |prompt| "first" }

    assert_raises(ArgumentError, "screen has been presented") do
      @app.screen(:duplicate_screen) { |prompt| "second" }
    end
  end

  def test_screen_adds_to_navigation_stack
    @app.screen(:nav_test) { |prompt| "result" }

    assert_includes @app.navigation_stack, :nav_test
  end

  def test_screen_returns_cached_value_if_present
    @app.session.set(:cached_screen, "cached_value")

    result = @app.screen(:cached_screen) { |prompt| "should_not_execute" }

    assert_equal "cached_value", result
    assert_includes @app.navigation_stack, :cached_screen
  end

  def test_screen_executes_block_when_no_cached_value
    executed = false
    result = @app.screen(:new_screen) do |prompt|
      executed = true
      assert_kind_of FlowChat::Prompt, prompt
      "block_result"
    end

    assert executed
    assert_equal "block_result", result
    assert_equal "block_result", @app.session.get(:new_screen)
  end

  def test_screen_clears_input_after_use
    @app.screen(:input_test) do |prompt|
      assert_equal "test_input", prompt.user_input
      "result"
    end

    assert_nil @app.input
  end

  def test_screen_with_prompt_asking_for_input
    # Create a new app with no input
    @context.input = nil
    app_no_input = FlowChat::Ussd::App.new(@context)

    # Since there's no input, the prompt should raise an interrupt
    error = assert_raises(FlowChat::Interrupt::Prompt) do
      app_no_input.screen(:prompt_screen) do |prompt|
        prompt.ask("What is your name?")
      end
    end

    assert_equal "What is your name?", error.prompt
    assert_includes app_no_input.navigation_stack, :prompt_screen
  end

  def test_screen_with_prompt_validation_failure
    @context.input = "12"

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      @app.screen(:validation_screen) do |prompt|
        prompt.ask("Enter age:",
          convert: ->(input) { input.to_i },
          validate: ->(input) { "Must be 18+" unless input >= 18 })
      end
    end

    assert_includes error.prompt, "Must be 18+"
  end

  def test_screen_with_successful_validation
    # Create app with valid input
    @context.input = "25"
    app_with_input = FlowChat::Ussd::App.new(@context)

    result = app_with_input.screen(:success_screen) do |prompt|
      prompt.ask("Enter age:",
        convert: ->(input) { input.to_i },
        validate: ->(input) { "Must be 18+" unless input >= 18 })
    end

    assert_equal 25, result
    assert_equal 25, app_with_input.session.get(:success_screen)
  end

  def test_say_raises_terminate_interrupt
    message = "Thank you for using our service!"

    error = assert_raises(FlowChat::Interrupt::Terminate) do
      @app.say(message)
    end

    assert_equal message, error.prompt
  end

  def test_multiple_screens_workflow
    # First request - user provides name
    @context.input = "John"
    app1 = FlowChat::Ussd::App.new(@context)
    name = app1.screen(:name) { |prompt| prompt.ask("Name?") }

    # Second request - user provides age (new app instance)
    @context.input = "25"
    app2 = FlowChat::Ussd::App.new(@context)
    age = app2.screen(:age) { |prompt| prompt.ask("Age?", convert: ->(i) { i.to_i }) }

    assert_equal "John", name
    assert_equal 25, age
    # Both apps share the same session, so both values should be stored
    assert_equal "John", @context.session.get(:name)
    assert_equal 25, @context.session.get(:age)
  end

  def test_message_id_returns_context_value
    @context["request.message_id"] = "uuid-test-123"
    assert_equal "uuid-test-123", @app.message_id
  end

  def test_message_id_returns_nil_when_not_set
    assert_nil @app.message_id
  end

  def test_timestamp_returns_context_value
    @context["request.timestamp"] = "2023-12-01T10:30:00Z"
    assert_equal "2023-12-01T10:30:00Z", @app.timestamp
  end

  def test_timestamp_returns_nil_when_not_set
    assert_nil @app.timestamp
  end

  def test_phone_number_returns_msisdn
    @context["request.msisdn"] = "+256700123456"
    assert_equal "+256700123456", @app.phone_number
  end

  def test_phone_number_returns_nil_when_not_set
    assert_nil @app.phone_number
  end

  def test_contact_name_returns_nil_for_ussd
    # USSD doesn't support contact names
    assert_nil @app.contact_name
  end

  def test_location_returns_nil_for_ussd
    # USSD doesn't support location sharing
    assert_nil @app.location
  end

  def test_media_returns_nil_for_ussd
    # USSD doesn't support media sharing
    assert_nil @app.media
  end

  def test_screen_with_select_prompt
    # Create app with selection input
    @context.input = "2"
    app_with_input = FlowChat::Ussd::App.new(@context)

    result = app_with_input.screen(:gender) do |prompt|
      prompt.select("Choose gender:", ["Male", "Female"])
    end

    assert_equal "Female", result
    assert_equal "Female", app_with_input.session.get(:gender)
  end

  def test_screen_with_yes_no_prompt
    # Create app with yes input
    @context.input = "1"  # Yes
    app_with_input = FlowChat::Ussd::App.new(@context)

    result = app_with_input.screen(:confirmation) do |prompt|
      prompt.yes?("Are you sure?")
    end

    assert_equal true, result
    assert_equal true, app_with_input.session.get(:confirmation)
  end
end

require "test_helper"

class WhatsappAppTest < Minitest::Test
  def setup
    @context = FlowChat::Context.new
    @context.session = create_test_session_store
    @context.input = "test_input"
    @context["request.contact_name"] = "John Doe"
    @context["request.message_id"] = "wamid.test123"
    @context["request.timestamp"] = "2023-12-01T10:30:00Z"
    @context["request.msisdn"] = "+256700000000"
    @context["request.location"] = {"latitude" => 0.3476, "longitude" => 32.5825}
    @context["request.media"] = {"type" => "image", "url" => "https://example.com/image.jpg"}

    # Set started_at to simulate ongoing conversation (not first message)
    @context.session.set("$started_at$", "2023-12-01T10:00:00Z")

    @app = FlowChat::Whatsapp::App.new(@context)
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

  def test_say_raises_terminate_interrupt_with_text_message
    message = "Thank you for using our service!"

    error = assert_raises(FlowChat::Interrupt::Terminate) do
      @app.say(message)
    end

    assert_equal message, error.prompt
    assert_nil error.media
  end

  def test_contact_name_returns_whatsapp_contact_name
    assert_equal "John Doe", @app.contact_name
  end

  def test_contact_name_returns_nil_when_not_set
    @context["request.contact_name"] = nil
    assert_nil @app.contact_name
  end

  def test_message_id_returns_whatsapp_message_id
    assert_equal "wamid.test123", @app.message_id
  end

  def test_message_id_returns_nil_when_not_set
    @context["request.message_id"] = nil
    assert_nil @app.message_id
  end

  def test_timestamp_returns_whatsapp_timestamp
    assert_equal "2023-12-01T10:30:00Z", @app.timestamp
  end

  def test_timestamp_returns_nil_when_not_set
    @context["request.timestamp"] = nil
    assert_nil @app.timestamp
  end

  def test_phone_number_returns_msisdn
    assert_equal "+256700000000", @app.phone_number
  end

  def test_phone_number_returns_nil_when_not_set
    @context["request.msisdn"] = nil
    assert_nil @app.phone_number
  end

  def test_location_returns_location_data
    expected_location = {"latitude" => 0.3476, "longitude" => 32.5825}
    assert_equal expected_location, @app.location
  end

  def test_location_returns_nil_when_not_set
    @context["request.location"] = nil
    assert_nil @app.location
  end

  def test_media_returns_media_data
    expected_media = {"type" => "image", "url" => "https://example.com/image.jpg"}
    assert_equal expected_media, @app.media
  end

  def test_media_returns_nil_when_not_set
    @context["request.media"] = nil
    assert_nil @app.media
  end

  def test_screen_with_prompt_asking_for_input
    # Create a new app with no input
    @context.input = nil
    app_no_input = FlowChat::Whatsapp::App.new(@context)

    # Since there's no input, the prompt should raise an interrupt
    error = assert_raises(FlowChat::Interrupt::Prompt) do
      app_no_input.screen(:prompt_screen) do |prompt|
        prompt.ask("What is your name?")
      end
    end

    assert_equal "What is your name?", error.prompt
    assert_nil error.choices
    assert_nil error.media
    assert_includes app_no_input.navigation_stack, :prompt_screen
  end

  def test_screen_with_select_prompt_buttons
    @context.input = nil
    app_no_input = FlowChat::Whatsapp::App.new(@context)

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      app_no_input.screen(:select_screen) do |prompt|
        prompt.select("Choose an option:", ["Yes", "No", "Maybe"])
      end
    end

    assert_equal "Choose an option:", error.prompt
    expected_choices = {1 => "Yes", 2 => "No", 3 => "Maybe"}
    assert_equal expected_choices, error.choices
    assert_nil error.media
  end

  def test_screen_with_select_prompt_list
    @context.input = nil
    app_no_input = FlowChat::Whatsapp::App.new(@context)

    items = (1..15).map { |i| "Option #{i}" }
    error = assert_raises(FlowChat::Interrupt::Prompt) do
      app_no_input.screen(:list_screen) do |prompt|
        prompt.select("Choose from list:", items)
      end
    end

    assert_equal "Choose from list:", error.prompt
    expected_choices = {}
    items.each_with_index { |item, index| expected_choices[index + 1] = item }
    assert_equal expected_choices, error.choices
    assert_nil error.media
  end

  def test_multiple_screens_workflow
    # Create session store that can be shared between app instances
    session_store = create_test_session_store
    # Set started_at to simulate ongoing conversation
    session_store.set("$started_at$", Time.current.iso8601)

    # First request - user provides name
    context1 = FlowChat::Context.new
    context1.input = "John"
    context1.session = session_store

    app1 = FlowChat::Whatsapp::App.new(context1)
    name = app1.screen(:name) { |prompt| prompt.ask("Name?") }

    # Second request - user provides age (new app instance, same session)
    context2 = FlowChat::Context.new
    context2.input = "25"
    context2.session = session_store  # Same session

    app2 = FlowChat::Whatsapp::App.new(context2)
    age = app2.screen(:age) { |prompt| prompt.ask("Age?", convert: ->(i) { i.to_i }) }

    assert_equal "John", name
    assert_equal 25, age
    # Both values should be stored in the shared session
    assert_equal "John", session_store.get(:name)
    assert_equal 25, session_store.get(:age)
  end

  def test_screen_with_validation_failure
    @context.input = "12"

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      @app.screen(:validation_screen) do |prompt|
        prompt.ask("Enter age:",
          convert: ->(input) { input.to_i },
          validate: ->(input) { "Must be 18+" unless input >= 18 })
      end
    end

    assert_includes error.prompt, "Must be 18+"
    assert_includes error.prompt, "Enter age:"
  end

  def test_screen_with_successful_validation
    @context.input = "25"
    app_with_input = FlowChat::Whatsapp::App.new(@context)

    result = app_with_input.screen(:success_screen) do |prompt|
      prompt.ask("Enter age:",
        convert: ->(input) { input.to_i },
        validate: ->(input) { "Must be 18+" unless input >= 18 })
    end

    assert_equal 25, result
    assert_equal 25, app_with_input.session.get(:success_screen)
  end

  def test_rich_message_handling_location
    @context.input = "$location$"
    app_with_location = FlowChat::Whatsapp::App.new(@context)

    result = app_with_location.screen(:location_screen) do |prompt|
      # Location input should be processed normally
      app_with_location.location
    end

    expected_location = {"latitude" => 0.3476, "longitude" => 32.5825}
    assert_equal expected_location, result
  end

  def test_rich_message_handling_media
    @context.input = "$media$"
    app_with_media = FlowChat::Whatsapp::App.new(@context)

    result = app_with_media.screen(:media_screen) do |prompt|
      # Media input should be processed normally
      app_with_media.media
    end

    expected_media = {"type" => "image", "url" => "https://example.com/image.jpg"}
    assert_equal expected_media, result
  end

  def test_initial_message_gets_nil_input_for_first_screen
    # Simulate someone sending "Hello" to start a conversation
    @context.input = "Hello"
    session_store = create_test_session_store
    # No $started_at$ in session, so this is the initial message
    @context.session = session_store

    app = FlowChat::Whatsapp::App.new(@context)

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      app.screen(:welcome) do |prompt|
        prompt.ask("Welcome! What's your name?")
      end
    end

    assert_equal "Welcome! What's your name?", error.prompt
    assert_nil error.choices
    assert_nil error.media

    # Should have set $started_at$
    refute_nil session_store.get("$started_at$")
    # App's internal input should be cleared after screen processing
    assert_nil app.input
  end

  def test_subsequent_messages_get_normal_input
    # Simulate ongoing conversation
    @context.input = "John"
    @context.session = create_test_session_store
    @context.session.set("$started_at$", "2023-12-01T10:00:00Z")  # Conversation already started
    app = FlowChat::Whatsapp::App.new(@context)

    # Subsequent screens should get the actual input
    result = app.screen(:name) do |prompt|
      prompt.ask("What's your name?")
    end

    assert_equal "John", result
    assert_equal "John", app.session.get(:name)
  end

  def test_started_at_timestamp_not_overwritten
    # Test that $started_at$ doesn't get overwritten if already set
    original_timestamp = "2023-12-01T10:00:00Z"
    @context.session.set("$started_at$", original_timestamp)

    app = FlowChat::Whatsapp::App.new(@context)
    app.screen(:second_screen) do |prompt|
      "result"
    end

    # Timestamp should remain unchanged
    assert_equal original_timestamp, app.session.get("$started_at$")
  end

  def test_complete_conversation_flow
    # Test the complete flow: initial message -> first prompt -> user response -> second prompt

    # Step 1: User sends initial message "Hi" to start conversation
    session_store = create_test_session_store
    @context.input = "Hi"
    @context.session = session_store

    app1 = FlowChat::Whatsapp::App.new(@context)

    error1 = assert_raises(FlowChat::Interrupt::Prompt) do
      app1.screen(:welcome) do |prompt|
        prompt.ask("Welcome! What's your name?")
      end
    end

    assert_equal "Welcome! What's your name?", error1.prompt
    assert_nil error1.choices
    assert_nil error1.media

    # At this point, session should have $started_at$ and app input should be cleared
    refute_nil session_store.get("$started_at$")
    assert_nil app1.input

    # Step 2: User responds with their name
    context2 = FlowChat::Context.new
    context2.input = "Alice"
    context2.session = session_store  # Same session

    app2 = FlowChat::Whatsapp::App.new(context2)

    name = app2.screen(:welcome) do |prompt|
      prompt.ask("Welcome! What's your name?")
    end

    assert_equal "Alice", name
    assert_equal "Alice", session_store.get(:welcome)
  end
end

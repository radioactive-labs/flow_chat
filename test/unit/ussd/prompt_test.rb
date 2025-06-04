require "test_helper"

class UssdPromptTest < Minitest::Test
  def test_ask_with_no_input_raises_prompt_interrupt
    prompt = FlowChat::Ussd::Prompt.new(nil)

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt.ask("What is your name?")
    end

    assert_equal "What is your name?", error.prompt
  end

  def test_ask_with_input_returns_input
    prompt = FlowChat::Ussd::Prompt.new("John")

    result = prompt.ask("What is your name?")
    assert_equal "John", result
  end

  def test_ask_with_convert_transforms_input
    prompt = FlowChat::Ussd::Prompt.new("25")

    result = prompt.ask("What is your age?", convert: ->(input) { input.to_i })
    assert_equal 25, result
    assert_kind_of Integer, result
  end

  def test_ask_with_validation_fails
    prompt = FlowChat::Ussd::Prompt.new("12")

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt.ask("What is your age?",
        convert: ->(input) { input.to_i },
        validate: ->(input) { "Must be at least 18" unless input >= 18 })
    end

    assert_includes error.prompt, "Must be at least 18"
    assert_includes error.prompt, "What is your age?"
  end

  def test_ask_with_validation_passes
    prompt = FlowChat::Ussd::Prompt.new("25")

    result = prompt.ask("What is your age?",
      convert: ->(input) { input.to_i },
      validate: ->(input) { "Must be at least 18" unless input >= 18 })

    assert_equal 25, result
  end

  def test_ask_with_transform_modifies_valid_input
    prompt = FlowChat::Ussd::Prompt.new("  john doe  ")

    result = prompt.ask("What is your name?", transform: ->(input) { input.strip.titleize })
    assert_equal "John Doe", result
  end

  def test_select_with_array_choices
    prompt = FlowChat::Ussd::Prompt.new("2")

    result = prompt.select("Choose gender", ["Male", "Female"])
    assert_equal "Female", result
  end

  def test_select_with_hash_choices
    prompt = FlowChat::Ussd::Prompt.new("1")
    choices = {"m" => "Male", "f" => "Female"}

    result = prompt.select("Choose gender", choices)
    assert_equal "m", result
  end

  def test_select_with_invalid_choice
    prompt = FlowChat::Ussd::Prompt.new("5")

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt.select("Choose gender", ["Male", "Female"])
    end

    assert_includes error.prompt, "Invalid selection"
  end

  def test_select_with_no_input_shows_choices
    prompt = FlowChat::Ussd::Prompt.new(nil)

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt.select("Choose gender", ["Male", "Female"])
    end

    assert_includes error.prompt, "Choose gender"
    expected_choices = {1 => "Male", 2 => "Female"}
    assert_equal expected_choices, error.choices
  end

  def test_yes_question_with_yes_answer
    prompt = FlowChat::Ussd::Prompt.new("1")  # "Yes" is first option

    result = prompt.yes?("Do you agree?")
    assert_equal true, result
  end

  def test_yes_question_with_no_answer
    prompt = FlowChat::Ussd::Prompt.new("2")  # "No" is second option

    result = prompt.yes?("Do you agree?")
    assert_equal false, result
  end

  def test_say_raises_terminate_interrupt
    prompt = FlowChat::Ussd::Prompt.new(nil)

    error = assert_raises(FlowChat::Interrupt::Terminate) do
      prompt.say("Thank you!")
    end

    assert_equal "Thank you!", error.prompt
  end

  def test_build_select_choices_with_array
    prompt = FlowChat::Ussd::Prompt.new(nil)
    choices = ["Option A", "Option B", "Option C"]

    result_choices, choices_prompt = prompt.send(:build_select_choices, choices)

    assert_equal choices, result_choices
    assert_equal({1 => "Option A", 2 => "Option B", 3 => "Option C"}, choices_prompt)
  end

  def test_build_select_choices_with_hash
    prompt = FlowChat::Ussd::Prompt.new(nil)
    choices = {"a" => "Option A", "b" => "Option B"}

    result_choices, choices_prompt = prompt.send(:build_select_choices, choices)

    assert_equal ["a", "b"], result_choices
    assert_equal({1 => "Option A", 2 => "Option B"}, choices_prompt)
  end

  def test_build_select_choices_with_invalid_type
    prompt = FlowChat::Ussd::Prompt.new(nil)

    assert_raises(ArgumentError) do
      prompt.send(:build_select_choices, "invalid")
    end
  end

  # ============================================================================
  # MEDIA SUPPORT TESTS
  # ============================================================================

  def test_ask_with_media_image_includes_url_in_prompt
    prompt = FlowChat::Ussd::Prompt.new(nil)

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt.ask("What do you think?", media: {
        type: :image,
        url: "https://example.com/image.jpg"
      })
    end

    expected_message = "What do you think?\n\n📷 Image: https://example.com/image.jpg"
    assert_equal expected_message, error.prompt
  end

  def test_ask_with_media_document_includes_url_in_prompt
    prompt = FlowChat::Ussd::Prompt.new(nil)

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt.ask("Review this document:", media: {
        type: :document,
        url: "https://example.com/doc.pdf"
      })
    end

    expected_message = "Review this document:\n\n📄 Document: https://example.com/doc.pdf"
    assert_equal expected_message, error.prompt
  end

  def test_ask_with_media_video_includes_url_in_prompt
    prompt = FlowChat::Ussd::Prompt.new(nil)

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt.ask("Rate this video:", media: {
        type: :video,
        url: "https://example.com/video.mp4"
      })
    end

    expected_message = "Rate this video:\n\n🎥 Video: https://example.com/video.mp4"
    assert_equal expected_message, error.prompt
  end

  def test_ask_with_media_audio_includes_url_in_prompt
    prompt = FlowChat::Ussd::Prompt.new(nil)

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt.ask("Listen to this:", media: {
        type: :audio,
        url: "https://example.com/audio.mp3"
      })
    end

    expected_message = "Listen to this:\n\n🎵 Audio: https://example.com/audio.mp3"
    assert_equal expected_message, error.prompt
  end

  def test_ask_with_media_sticker_includes_url_in_prompt
    prompt = FlowChat::Ussd::Prompt.new(nil)

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt.ask("React to this:", media: {
        type: :sticker,
        url: "https://example.com/sticker.webp"
      })
    end

    expected_message = "React to this:\n\n😊 Sticker: https://example.com/sticker.webp"
    assert_equal expected_message, error.prompt
  end

  def test_ask_with_media_unknown_type_uses_generic_icon
    prompt = FlowChat::Ussd::Prompt.new(nil)

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt.ask("Check this out:", media: {
        type: :unknown,
        url: "https://example.com/file"
      })
    end

    expected_message = "Check this out:\n\n📎 Media: https://example.com/file"
    assert_equal expected_message, error.prompt
  end

  def test_ask_with_media_using_path_key
    prompt = FlowChat::Ussd::Prompt.new(nil)

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt.ask("What do you think?", media: {
        type: :image,
        path: "/path/to/image.jpg"  # Using path instead of url
      })
    end

    expected_message = "What do you think?\n\n📷 Image: /path/to/image.jpg"
    assert_equal expected_message, error.prompt
  end

  def test_ask_with_media_and_input_returns_input
    prompt = FlowChat::Ussd::Prompt.new("user response")

    result = prompt.ask("What do you think?", media: {
      type: :image,
      url: "https://example.com/image.jpg"
    })

    assert_equal "user response", result
  end

  def test_ask_without_media_works_normally
    prompt = FlowChat::Ussd::Prompt.new(nil)

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt.ask("What is your name?")
    end

    assert_equal "What is your name?", error.prompt
  end

  def test_say_with_media_image_includes_url_in_message
    prompt = FlowChat::Ussd::Prompt.new(nil)

    error = assert_raises(FlowChat::Interrupt::Terminate) do
      prompt.say("Here's your image:", media: {
        type: :image,
        url: "https://example.com/image.jpg"
      })
    end

    expected_message = "Here's your image:\n\n📷 Image: https://example.com/image.jpg"
    assert_equal expected_message, error.prompt
  end

  def test_say_with_media_document_includes_url_in_message
    prompt = FlowChat::Ussd::Prompt.new(nil)

    error = assert_raises(FlowChat::Interrupt::Terminate) do
      prompt.say("Here's your receipt:", media: {
        type: :document,
        url: "https://example.com/receipt.pdf"
      })
    end

    expected_message = "Here's your receipt:\n\n📄 Document: https://example.com/receipt.pdf"
    assert_equal expected_message, error.prompt
  end

  def test_say_without_media_works_normally
    prompt = FlowChat::Ussd::Prompt.new(nil)

    error = assert_raises(FlowChat::Interrupt::Terminate) do
      prompt.say("Thank you!")
    end

    assert_equal "Thank you!", error.prompt
  end

  def test_select_does_not_support_media
    prompt = FlowChat::Ussd::Prompt.new(nil)

    # select method should not accept media parameter
    # This should work fine without media
    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt.select("Choose gender", ["Male", "Female"])
    end

    assert_includes error.prompt, "Choose gender"
    expected_choices = {1 => "Male", 2 => "Female"}
    assert_equal expected_choices, error.choices
  end

  def test_yes_does_not_support_media
    prompt = FlowChat::Ussd::Prompt.new(nil)

    # yes? method should not accept media parameter
    # This should work fine without media
    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt.yes?("Do you agree?")
    end

    assert_includes error.prompt, "Do you agree?"
  end

  def test_build_message_with_media_defaults_to_image_type
    prompt = FlowChat::Ussd::Prompt.new(nil)

    result = prompt.send(:build_message_with_media, "Test message", {
      url: "https://example.com/file"
      # No type specified, should default to :image
    })

    expected_message = "Test message\n\n📷 Image: https://example.com/file"
    assert_equal expected_message, result
  end

  def test_build_message_with_media_returns_original_message_if_no_media
    prompt = FlowChat::Ussd::Prompt.new(nil)

    result = prompt.send(:build_message_with_media, "Original message", nil)
    assert_equal "Original message", result
  end

  def test_media_works_with_existing_validation_and_conversion
    prompt = FlowChat::Ussd::Prompt.new("25")

    result = prompt.ask("Enter your age:",
      media: {type: :image, url: "https://example.com/age_help.jpg"},
      convert: ->(input) { input.to_i },
      validate: ->(input) { "Must be at least 18" unless input >= 18 })

    assert_equal 25, result
  end

  def test_media_validation_error_includes_media_url
    prompt = FlowChat::Ussd::Prompt.new("12")

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt.ask("Enter your age:",
        media: {type: :image, url: "https://example.com/age_help.jpg"},
        convert: ->(input) { input.to_i },
        validate: ->(input) { "Must be at least 18" unless input >= 18 })
    end

    # Validation error should include both error message and original prompt with media
    assert_includes error.prompt, "Must be at least 18"
    assert_includes error.prompt, "Enter your age:"
    assert_includes error.prompt, "📷 Image: https://example.com/age_help.jpg"
  end
end

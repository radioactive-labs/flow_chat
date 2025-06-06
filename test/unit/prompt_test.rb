require "test_helper"

class PromptTest < Minitest::Test
  def test_initializes_with_user_input
    prompt = FlowChat::Prompt.new("test_input")
    assert_equal "test_input", prompt.user_input
  end

  def test_ask_with_no_input_raises_prompt_interrupt
    prompt = FlowChat::Prompt.new(nil)

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt.ask("What is your name?")
    end

    assert_equal "What is your name?", error.prompt
  end

  def test_ask_with_input_returns_input
    prompt = FlowChat::Prompt.new("John")

    result = prompt.ask("What is your name?")
    assert_equal "John", result
  end

  def test_ask_with_transform_transforms_input
    prompt = FlowChat::Prompt.new("25")

    result = prompt.ask("What is your age?", transform: ->(input) { input.to_i })
    assert_equal 25, result
    assert_kind_of Integer, result
  end

  def test_ask_with_validation_fails
    prompt = FlowChat::Prompt.new("12")

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt.ask("What is your age?",
        validate: ->(input) { "Must be at least 18" unless input.to_i >= 18 },
        transform: ->(input) { input.to_i })
    end

    assert_includes error.prompt, "Must be at least 18"
    assert_includes error.prompt, "What is your age?"
  end

  def test_ask_with_validation_passes
    prompt = FlowChat::Prompt.new("25")

    result = prompt.ask("What is your age?",
      validate: ->(input) { "Must be at least 18" unless input.to_i >= 18 },
      transform: ->(input) { input.to_i })

    assert_equal 25, result
  end

  def test_ask_with_transform_modifies_valid_input
    prompt = FlowChat::Prompt.new("  john doe  ")

    result = prompt.ask("What is your name?", transform: ->(input) { input.strip.titleize })
    assert_equal "John Doe", result
  end

  def test_select_with_array_choices
    prompt = FlowChat::Prompt.new("Female")

    result = prompt.select("Choose gender", ["Male", "Female"])
    assert_equal "Female", result
  end

  def test_select_with_hash_choices
    prompt = FlowChat::Prompt.new("m")
    choices = {"m" => "Male", "f" => "Female"}

    result = prompt.select("Choose gender", choices)
    assert_equal "m", result
  end

  def test_select_with_invalid_choice
    prompt = FlowChat::Prompt.new("Other")

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt.select("Choose gender", ["Male", "Female"])
    end

    assert_includes error.prompt, "Invalid selection"
  end

  def test_select_with_no_input_shows_choices
    prompt = FlowChat::Prompt.new(nil)

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt.select("Choose gender", ["Male", "Female"])
    end

    assert_includes error.prompt, "Choose gender"
    # New Prompt implementation normalizes array choices to hash format
    expected_choices = {"Male" => "Male", "Female" => "Female"}
    assert_equal expected_choices, error.choices
  end

  def test_yes_question_with_yes_answer
    prompt = FlowChat::Prompt.new("Yes")

    result = prompt.yes?("Do you agree?")
    assert_equal true, result
  end

  def test_yes_question_with_no_answer
    prompt = FlowChat::Prompt.new("No")

    result = prompt.yes?("Do you agree?")
    assert_equal false, result
  end

  def test_say_raises_terminate_interrupt
    prompt = FlowChat::Prompt.new(nil)

    error = assert_raises(FlowChat::Interrupt::Terminate) do
      prompt.say("Thank you!")
    end

    assert_equal "Thank you!", error.prompt
  end

  # NOTE: build_select_choices method was removed in the new Prompt implementation.
  # Choice normalization now happens automatically in the normalize_choices method.
  # These tests are no longer relevant as the behavior is tested via select() method tests.

  # ============================================================================
  # MEDIA SUPPORT TESTS
  # ============================================================================

  def test_ask_with_media_image_includes_url_in_prompt
    prompt = FlowChat::Prompt.new(nil)

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt.ask("What do you think?", media: {
        type: :image,
        url: "https://example.com/image.jpg"
      })
    end

    # After architectural unification: raw message + media attribute
    assert_equal "What do you think?", error.prompt
    assert_equal :image, error.media[:type]
    assert_equal "https://example.com/image.jpg", error.media[:url]
  end

  def test_ask_with_media_document_includes_url_in_prompt
    prompt = FlowChat::Prompt.new(nil)

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt.ask("Review this document:", media: {
        type: :document,
        url: "https://example.com/doc.pdf"
      })
    end

    # After architectural unification: raw message + media attribute
    assert_equal "Review this document:", error.prompt
    assert_equal :document, error.media[:type]
    assert_equal "https://example.com/doc.pdf", error.media[:url]
  end

  def test_ask_with_media_video_includes_url_in_prompt
    prompt = FlowChat::Prompt.new(nil)

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt.ask("Rate this video:", media: {
        type: :video,
        url: "https://example.com/video.mp4"
      })
    end

    # After architectural unification: raw message + media attribute
    assert_equal "Rate this video:", error.prompt
    assert_equal :video, error.media[:type]
    assert_equal "https://example.com/video.mp4", error.media[:url]
  end

  def test_ask_with_media_audio_includes_url_in_prompt
    prompt = FlowChat::Prompt.new(nil)

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt.ask("Listen to this:", media: {
        type: :audio,
        url: "https://example.com/audio.mp3"
      })
    end

    # After architectural unification: raw message + media attribute
    assert_equal "Listen to this:", error.prompt
    assert_equal :audio, error.media[:type]
    assert_equal "https://example.com/audio.mp3", error.media[:url]
  end

  def test_ask_with_media_sticker_includes_url_in_prompt
    prompt = FlowChat::Prompt.new(nil)

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt.ask("React to this:", media: {
        type: :sticker,
        url: "https://example.com/sticker.webp"
      })
    end

    # After architectural unification: raw message + media attribute
    assert_equal "React to this:", error.prompt
    assert_equal :sticker, error.media[:type]
    assert_equal "https://example.com/sticker.webp", error.media[:url]
  end

  def test_ask_with_media_unknown_type_uses_generic_icon
    prompt = FlowChat::Prompt.new(nil)

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt.ask("Check this out:", media: {
        type: :unknown,
        url: "https://example.com/file"
      })
    end

    # After architectural unification: raw message + media attribute
    assert_equal "Check this out:", error.prompt
    assert_equal :unknown, error.media[:type]
    assert_equal "https://example.com/file", error.media[:url]
  end

  def test_ask_with_media_using_path_key
    prompt = FlowChat::Prompt.new(nil)

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt.ask("What do you think?", media: {
        type: :image,
        path: "/path/to/image.jpg"  # Using path instead of url
      })
    end

    # After architectural unification: raw message + media attribute
    assert_equal "What do you think?", error.prompt
    assert_equal :image, error.media[:type]
    assert_equal "/path/to/image.jpg", error.media[:path]
  end

  def test_ask_with_media_and_input_returns_input
    prompt = FlowChat::Prompt.new("user response")

    result = prompt.ask("What do you think?", media: {
      type: :image,
      url: "https://example.com/image.jpg"
    })

    assert_equal "user response", result
  end

  def test_ask_without_media_works_normally
    prompt = FlowChat::Prompt.new(nil)

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt.ask("What is your name?")
    end

    assert_equal "What is your name?", error.prompt
    assert_nil error.media
  end

  def test_say_with_media_image_includes_url_in_message
    prompt = FlowChat::Prompt.new(nil)

    error = assert_raises(FlowChat::Interrupt::Terminate) do
      prompt.say("Here's your image:", media: {
        type: :image,
        url: "https://example.com/image.jpg"
      })
    end

    # After architectural unification: raw message + media attribute
    assert_equal "Here's your image:", error.prompt
    assert_equal :image, error.media[:type]
    assert_equal "https://example.com/image.jpg", error.media[:url]
  end

  def test_say_with_media_document_includes_url_in_message
    prompt = FlowChat::Prompt.new(nil)

    error = assert_raises(FlowChat::Interrupt::Terminate) do
      prompt.say("Here's your receipt:", media: {
        type: :document,
        url: "https://example.com/receipt.pdf"
      })
    end

    # After architectural unification: raw message + media attribute
    assert_equal "Here's your receipt:", error.prompt
    assert_equal :document, error.media[:type]
    assert_equal "https://example.com/receipt.pdf", error.media[:url]
  end

  def test_say_without_media_works_normally
    prompt = FlowChat::Prompt.new(nil)

    error = assert_raises(FlowChat::Interrupt::Terminate) do
      prompt.say("Thank you!")
    end

    assert_equal "Thank you!", error.prompt
    assert_nil error.media
  end

  def test_select_does_not_support_media
    prompt = FlowChat::Prompt.new(nil)

    # select method should not accept media parameter
    # This should work fine without media
    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt.select("Choose gender", ["Male", "Female"])
    end

    assert_includes error.prompt, "Choose gender"
    # New Prompt implementation normalizes array choices to hash format
    expected_choices = {"Male" => "Male", "Female" => "Female"}
    assert_equal expected_choices, error.choices
  end

  def test_yes_does_not_support_media
    prompt = FlowChat::Prompt.new(nil)

    # yes? method should not accept media parameter
    # This should work fine without media
    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt.yes?("Do you agree?")
    end

    assert_includes error.prompt, "Do you agree?"
  end

  def test_media_works_with_existing_validation_and_conversion
    prompt = FlowChat::Prompt.new("25")

    result = prompt.ask("Enter your age:",
      media: {type: :image, url: "https://example.com/age_help.jpg"},
      validate: ->(input) { "Must be at least 18" unless input.to_i >= 18 },
      transform: ->(input) { input.to_i })

    assert_equal 25, result
  end

  def test_media_validation_error_includes_media_url
    prompt = FlowChat::Prompt.new("12")

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt.ask("Enter your age:",
        media: {type: :image, url: "https://example.com/age_help.jpg"},
        validate: ->(input) { "Must be at least 18" unless input.to_i >= 18 },
        transform: ->(input) { input.to_i })
    end

    # Validation error should include both error message and original prompt
    assert_includes error.prompt, "Must be at least 18"
    assert_includes error.prompt, "Enter your age:"
    # Media should be in separate attribute
    assert_equal :image, error.media[:type]
    assert_equal "https://example.com/age_help.jpg", error.media[:url]
  end

  def test_combine_validation_error_with_message_enabled_by_default
    prompt = FlowChat::Prompt.new("12")
    
    # Default behavior should combine error with original message
    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt.ask("Enter your age:",
        validate: ->(input) { "Must be at least 18" unless input.to_i >= 18 },
        transform: ->(input) { input.to_i })
    end

    assert_includes error.prompt, "Must be at least 18"
    assert_includes error.prompt, "Enter your age:"
  end

  def test_combine_validation_error_with_message_disabled_shows_only_error
    original_setting = FlowChat::Config.combine_validation_error_with_message
    FlowChat::Config.combine_validation_error_with_message = false

    prompt = FlowChat::Prompt.new("12")
    
    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt.ask("Enter your age:",
        validate: ->(input) { "Must be at least 18" unless input.to_i >= 18 },
        transform: ->(input) { input.to_i })
    end

    assert_includes error.prompt, "Must be at least 18"
    refute_includes error.prompt, "Enter your age:"
  ensure
    FlowChat::Config.combine_validation_error_with_message = original_setting
  end

  def test_combine_validation_error_with_message_enabled_shows_both_messages
    original_setting = FlowChat::Config.combine_validation_error_with_message
    FlowChat::Config.combine_validation_error_with_message = true

    prompt = FlowChat::Prompt.new("12")
    
    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt.ask("Enter your age:",
        validate: ->(input) { "Must be at least 18" unless input.to_i >= 18 },
        transform: ->(input) { input.to_i })
    end

    assert_equal "Must be at least 18\n\nEnter your age:", error.prompt
  ensure
    FlowChat::Config.combine_validation_error_with_message = original_setting
  end

  # ============================================================================
  # MEDIA WITH CHOICES VALIDATION TESTS
  # ============================================================================

  def test_ask_with_media_and_few_choices_works
    prompt = FlowChat::Prompt.new(nil)

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt.ask("Choose size:", 
        choices: ["Small", "Medium", "Large"], 
        media: {type: :image, url: "https://example.com/sizes.jpg"})
    end

    assert_equal "Choose size:", error.prompt
    # New Prompt implementation normalizes array choices to hash format
    assert_equal({"Small" => "Small", "Medium" => "Medium", "Large" => "Large"}, error.choices)
    assert_equal({type: :image, url: "https://example.com/sizes.jpg"}, error.media)
  end

  def test_ask_with_media_and_many_choices_fails
    prompt = FlowChat::Prompt.new(nil)

    error = assert_raises(ArgumentError) do
      prompt.ask("Choose color:", 
        choices: ["Red", "Blue", "Green", "Yellow", "Purple"], 
        media: {type: :image, url: "https://example.com/colors.jpg"})
    end

    assert_equal "Media with more than 3 choices is not supported. Please use either media OR choices for more than 3 options.", error.message
  end

  def test_ask_with_media_and_exactly_three_choices_works
    prompt = FlowChat::Prompt.new(nil)

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt.ask("Pick one:", 
        choices: ["Option A", "Option B", "Option C"], 
        media: {type: :video, url: "https://example.com/demo.mp4"})
    end

    assert_equal "Pick one:", error.prompt
    assert_equal 3, error.choices.length
    assert_equal :video, error.media[:type]
  end

  def test_ask_with_media_and_hash_choices_validates_count
    prompt = FlowChat::Prompt.new(nil)

    # Hash with 3 choices should work
    begin
      prompt.ask("Choose:", 
        choices: {"a" => "Alpha", "b" => "Beta", "c" => "Gamma"}, 
        media: {type: :image, url: "https://example.com/image.jpg"})
    rescue FlowChat::Interrupt::Prompt
      # Expected interrupt, validation passed
    rescue ArgumentError => e
      flunk "Should not raise ArgumentError for 3 choices: #{e.message}"
    end

    # Hash with 4 choices should fail
    error = assert_raises(ArgumentError) do
      prompt.ask("Choose:", 
        choices: {"a" => "Alpha", "b" => "Beta", "c" => "Gamma", "d" => "Delta"}, 
        media: {type: :image, url: "https://example.com/image.jpg"})
    end

    assert_includes error.message, "Media with more than 3 choices is not supported"
  end

  def test_ask_with_choices_but_no_media_allows_many_choices
    prompt = FlowChat::Prompt.new(nil)

    # Should work fine with many choices when no media
    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt.ask("Choose from menu:", 
        choices: (1..10).map { |i| "Option #{i}" })
    end

    assert_equal 10, error.choices.length
    assert_nil error.media
  end

  def test_ask_with_media_but_no_choices_works
    prompt = FlowChat::Prompt.new(nil)

    # Should work fine with media when no choices
    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt.ask("Look at this:", 
        media: {type: :image, url: "https://example.com/image.jpg"})
    end

    assert_nil error.choices
    assert_equal :image, error.media[:type]
  end

  def test_select_with_media_and_few_choices_works
    prompt = FlowChat::Prompt.new(nil)

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt.select("Rate this image:", 
        ["⭐", "⭐⭐", "⭐⭐⭐"], 
        media: {type: :image, url: "https://example.com/photo.jpg"})
    end

    assert_includes error.prompt, "Rate this image:"
    assert_equal 3, error.choices.length
    assert_equal :image, error.media[:type]
  end

  def test_select_with_media_and_many_choices_fails
    prompt = FlowChat::Prompt.new(nil)

    error = assert_raises(ArgumentError) do
      prompt.select("Choose difficulty:", 
        ["Easy", "Medium", "Hard", "Expert", "Nightmare"], 
        media: {type: :image, url: "https://example.com/difficulty.jpg"})
    end

    assert_includes error.message, "Media with more than 3 choices is not supported"
  end

  def test_yes_question_with_media_works
    prompt = FlowChat::Prompt.new(nil)

    # yes? method creates exactly 2 choices, so should work with media
    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt.yes?("Do you like this image?")
    end

    assert_includes error.prompt, "Do you like this image?"
    # New Prompt implementation normalizes choices to hash format
    assert_equal({"Yes" => "Yes", "No" => "No"}, error.choices)
  end

  def test_validation_occurs_for_both_ask_and_select_methods
    prompt = FlowChat::Prompt.new(nil)
    media = {type: :image, url: "https://example.com/test.jpg"}
    many_choices = ["A", "B", "C", "D", "E"]

    # Both ask and select should validate
    assert_raises(ArgumentError) { prompt.ask("Test", choices: many_choices, media: media) }
    assert_raises(ArgumentError) { prompt.select("Test", many_choices, media: media) }
  end
end 
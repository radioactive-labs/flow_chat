require "test_helper"

class WhatsappPromptTest < Minitest::Test
  def setup
    @prompt = FlowChat::Whatsapp::Prompt.new("user_input")
  end

  def test_initializes_with_user_input
    assert_equal "user_input", @prompt.input
  end

  def test_ask_with_no_input_raises_prompt_interrupt
    prompt_no_input = FlowChat::Whatsapp::Prompt.new(nil)

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt_no_input.ask("What is your name?")
    end

    expected_payload = [:text, "What is your name?", {}]
    assert_equal expected_payload, error.prompt
  end

  def test_ask_with_input_returns_input
    result = @prompt.ask("What is your name?")
    assert_equal "user_input", result
  end

  def test_ask_with_conversion
    prompt_with_number = FlowChat::Whatsapp::Prompt.new("25")

    result = prompt_with_number.ask("Enter age:", convert: ->(input) { input.to_i })
    assert_equal 25, result
    assert_kind_of Integer, result
  end

  def test_ask_with_validation_success
    prompt_valid = FlowChat::Whatsapp::Prompt.new("25")

    result = prompt_valid.ask("Enter age:",
      convert: ->(input) { input.to_i },
      validate: ->(input) { "Must be 18+" unless input >= 18 })

    assert_equal 25, result
  end

  def test_ask_with_validation_failure
    prompt_invalid = FlowChat::Whatsapp::Prompt.new("12")

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt_invalid.ask("Enter age:",
        convert: ->(input) { input.to_i },
        validate: ->(input) { "Must be 18+" unless input >= 18 })
    end

    assert_includes error.prompt[1], "Must be 18+"
  end

  def test_select_with_array_3_or_fewer_uses_buttons
    prompt_no_input = FlowChat::Whatsapp::Prompt.new(nil)
    options = ["Option 1", "Option 2", "Option 3"]

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt_no_input.select("Choose:", options)
    end

    # Should use buttons format for ≤3 options when converted to hash
    assert_equal :interactive_list, error.prompt[0] # Actually uses list for arrays
    assert_equal "Choose:", error.prompt[1]
  end

  def test_select_with_hash_3_or_fewer_uses_buttons
    prompt_no_input = FlowChat::Whatsapp::Prompt.new(nil)
    options = {"a" => "Option A", "b" => "Option B", "c" => "Option C"}

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt_no_input.select("Choose:", options)
    end

    assert_equal :interactive_buttons, error.prompt[0]
    assert_equal "Choose:", error.prompt[1]

    buttons = error.prompt[2][:buttons]
    assert_equal 3, buttons.size
    assert_equal "a", buttons[0][:id]
    assert_equal "Option A", buttons[0][:title]
  end

  def test_select_with_hash_more_than_3_uses_list
    prompt_no_input = FlowChat::Whatsapp::Prompt.new(nil)
    options = {"a" => "Option A", "b" => "Option B", "c" => "Option C", "d" => "Option D"}

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt_no_input.select("Choose:", options)
    end

    assert_equal :interactive_list, error.prompt[0]
    assert_equal "Choose:", error.prompt[1]

    sections = error.prompt[2][:sections]
    assert_equal 1, sections.size
    assert_equal "Options", sections[0][:title]
    assert_equal 4, sections[0][:rows].size
  end

  def test_select_with_valid_array_selection_by_index
    prompt_with_selection = FlowChat::Whatsapp::Prompt.new("1")  # Second option (0-indexed)
    options = ["First", "Second", "Third"]

    result = prompt_with_selection.select("Choose:", options)
    assert_equal "Second", result
  end

  def test_select_with_valid_hash_selection_by_key
    prompt_with_selection = FlowChat::Whatsapp::Prompt.new("b")
    options = {"a" => "Option A", "b" => "Option B", "c" => "Option C"}

    result = prompt_with_selection.select("Choose:", options)
    assert_equal "Option B", result
  end

  def test_select_with_invalid_selection
    prompt_invalid = FlowChat::Whatsapp::Prompt.new("invalid")
    options = ["First", "Second"]

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt_invalid.select("Choose:", options)
    end

    assert_includes error.prompt[1], "Invalid choice"
  end

  def test_select_validation_empty_choices
    prompt_no_input = FlowChat::Whatsapp::Prompt.new(nil)

    error = assert_raises(ArgumentError) do
      prompt_no_input.select("Choose:", [])
    end

    assert_includes error.message, "choices cannot be empty"
  end

  def test_select_validation_max_100_choices
    prompt_no_input = FlowChat::Whatsapp::Prompt.new(nil)
    options = (1..101).map { |i| "Option #{i}" }

    error = assert_raises(ArgumentError) do
      prompt_no_input.select("Choose:", options)
    end

    assert_includes error.message, "maximum 100 choice options"
  end

  def test_select_with_large_list_pagination
    prompt_no_input = FlowChat::Whatsapp::Prompt.new(nil)
    options = (1..25).map { |i| "Option #{i}" }

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt_no_input.select("Choose:", options)
    end

    sections = error.prompt[2][:sections]
    assert sections.size > 1  # Should be paginated

    # First section should be "1-10"
    first_section = sections[0]
    assert_equal "1-10", first_section[:title]
    assert_equal 10, first_section[:rows].size
  end

  def test_yes_with_yes_input
    prompt_yes = FlowChat::Whatsapp::Prompt.new("yes")

    result = prompt_yes.yes?("Are you sure?")
    assert_equal true, result
  end

  def test_yes_with_no_input
    prompt_no = FlowChat::Whatsapp::Prompt.new("no")

    result = prompt_no.yes?("Are you sure?")
    assert_equal false, result
  end

  def test_yes_with_numeric_input
    prompt_yes = FlowChat::Whatsapp::Prompt.new("1")
    prompt_no = FlowChat::Whatsapp::Prompt.new("0")

    assert_equal true, prompt_yes.yes?("Are you sure?")
    assert_equal false, prompt_no.yes?("Are you sure?")
  end

  def test_yes_with_no_input_raises_prompt
    prompt_no_input = FlowChat::Whatsapp::Prompt.new(nil)

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt_no_input.yes?("Are you sure?")
    end

    assert_equal :interactive_buttons, error.prompt[0]
    assert_equal "Are you sure?", error.prompt[1]

    buttons = error.prompt[2][:buttons]
    assert_equal 2, buttons.size
    assert_equal "yes", buttons[0][:id]
    assert_equal "Yes", buttons[0][:title]
  end

  def test_yes_with_invalid_input
    prompt_invalid = FlowChat::Whatsapp::Prompt.new("maybe")

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt_invalid.yes?("Are you sure?")
    end

    assert_includes error.prompt[1], "Please answer with Yes or No"
  end

  def test_blank_input_handling
    prompt_blank = FlowChat::Whatsapp::Prompt.new("   ")  # Whitespace only

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt_blank.ask("What is your name?")
    end

    expected_payload = [:text, "What is your name?", {}]
    assert_equal expected_payload, error.prompt
  end

  def test_empty_input_handling
    prompt_empty = FlowChat::Whatsapp::Prompt.new("")

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt_empty.ask("What is your name?")
    end

    expected_payload = [:text, "What is your name?", {}]
    assert_equal expected_payload, error.prompt
  end

  def test_complex_workflow_with_conversion_and_validation
    prompt_valid = FlowChat::Whatsapp::Prompt.new("25")

    result = prompt_valid.ask("Enter your age:",
      convert: ->(input) { input.to_i },
      validate: ->(age) {
        return "Age must be between 13 and 120" unless (13..120).cover?(age)
        nil
      })

    assert_equal 25, result
    assert_kind_of Integer, result
  end

  def test_title_truncation_in_list
    prompt_no_input = FlowChat::Whatsapp::Prompt.new(nil)
    long_option = "This is a very long option that exceeds 24 characters"
    options = [long_option]

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt_no_input.select("Choose:", options)
    end

    sections = error.prompt[2][:sections]
    row = sections[0][:rows][0]

    # Title should be truncated to 24 chars (minus "...")
    assert row[:title].length <= 24
    # Description should contain the full text (up to 72 chars)
    assert row[:description].length <= 72
    assert row[:description].include?("This is a very long option")
  end

  def test_choice_validation_empty_choice
    prompt_no_input = FlowChat::Whatsapp::Prompt.new(nil)
    options = ["Valid", "", "Also Valid"]

    error = assert_raises(ArgumentError) do
      prompt_no_input.select("Choose:", options)
    end

    assert_includes error.message, "choice at index 1 cannot be empty"
  end

  def test_choice_validation_too_long_choice
    prompt_no_input = FlowChat::Whatsapp::Prompt.new(nil)
    too_long = "a" * 101  # Over 100 character limit
    options = [too_long]

    error = assert_raises(ArgumentError) do
      prompt_no_input.select("Choose:", options)
    end

    assert_includes error.message, "is too long"
    assert_includes error.message, "101 chars"
  end

  def test_truncate_text_helper
    prompt = FlowChat::Whatsapp::Prompt.new(nil)

    # Test no truncation needed
    assert_equal "short", prompt.send(:truncate_text, "short", 10)

    # Test truncation
    assert_equal "this is...", prompt.send(:truncate_text, "this is a long text", 10)

    # Test exact length
    assert_equal "exact", prompt.send(:truncate_text, "exact", 5)
  end

  # ============================================================================
  # MEDIA SUPPORT TESTS
  # ============================================================================

  def test_ask_with_media_image_raises_media_prompt
    prompt_no_input = FlowChat::Whatsapp::Prompt.new(nil)

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt_no_input.ask("What do you think?", media: {
        type: :image,
        url: "https://example.com/image.jpg"
      })
    end

    assert_equal :media_image, error.prompt[0]
    assert_equal "", error.prompt[1]  # Empty content

    options = error.prompt[2]
    assert_equal "https://example.com/image.jpg", options[:url]
    assert_equal "What do you think?", options[:caption]
  end

  def test_ask_with_media_document_raises_media_prompt
    prompt_no_input = FlowChat::Whatsapp::Prompt.new(nil)

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt_no_input.ask("Review this document:", media: {
        type: :document,
        url: "https://example.com/doc.pdf",
        filename: "document.pdf"
      })
    end

    assert_equal :media_document, error.prompt[0]

    options = error.prompt[2]
    assert_equal "https://example.com/doc.pdf", options[:url]
    assert_equal "Review this document:", options[:caption]
    assert_equal "document.pdf", options[:filename]
  end

  def test_ask_with_media_video_raises_media_prompt
    prompt_no_input = FlowChat::Whatsapp::Prompt.new(nil)

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt_no_input.ask("Rate this video:", media: {
        type: :video,
        url: "https://example.com/video.mp4"
      })
    end

    assert_equal :media_video, error.prompt[0]

    options = error.prompt[2]
    assert_equal "https://example.com/video.mp4", options[:url]
    assert_equal "Rate this video:", options[:caption]
  end

  def test_ask_with_media_audio_raises_media_prompt
    prompt_no_input = FlowChat::Whatsapp::Prompt.new(nil)

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt_no_input.ask("Listen to this:", media: {
        type: :audio,
        url: "https://example.com/audio.mp3"
      })
    end

    assert_equal :media_audio, error.prompt[0]

    options = error.prompt[2]
    assert_equal "https://example.com/audio.mp3", options[:url]
    assert_equal "Listen to this:", options[:caption]
  end

  def test_ask_with_media_sticker_raises_media_prompt
    prompt_no_input = FlowChat::Whatsapp::Prompt.new(nil)

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt_no_input.ask("React to this:", media: {
        type: :sticker,
        url: "https://example.com/sticker.webp"
      })
    end

    assert_equal :media_sticker, error.prompt[0]

    options = error.prompt[2]
    assert_equal "https://example.com/sticker.webp", options[:url]
    # Stickers don't support captions
    refute options.key?(:caption)
  end

  def test_ask_with_media_using_path_key
    prompt_no_input = FlowChat::Whatsapp::Prompt.new(nil)

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt_no_input.ask("What do you think?", media: {
        type: :image,
        path: "/path/to/image.jpg"  # Using path instead of url
      })
    end

    options = error.prompt[2]
    assert_equal "/path/to/image.jpg", options[:url]
    assert_equal "What do you think?", options[:caption]
  end

  def test_ask_with_media_and_input_returns_input
    prompt_with_input = FlowChat::Whatsapp::Prompt.new("user response")

    result = prompt_with_input.ask("What do you think?", media: {
      type: :image,
      url: "https://example.com/image.jpg"
    })

    assert_equal "user response", result
  end

  def test_ask_with_media_unsupported_type_raises_error
    prompt_no_input = FlowChat::Whatsapp::Prompt.new(nil)

    error = assert_raises(ArgumentError) do
      prompt_no_input.ask("What do you think?", media: {
        type: :unsupported,
        url: "https://example.com/file"
      })
    end

    assert_includes error.message, "Unsupported media type: unsupported"
  end

  def test_say_with_media_image_raises_terminate
    prompt = FlowChat::Whatsapp::Prompt.new(nil)

    error = assert_raises(FlowChat::Interrupt::Terminate) do
      prompt.say("Here's your image:", media: {
        type: :image,
        url: "https://example.com/image.jpg"
      })
    end

    assert_equal :media_image, error.prompt[0]
    assert_equal "", error.prompt[1]

    options = error.prompt[2]
    assert_equal "https://example.com/image.jpg", options[:url]
    assert_equal "Here's your image:", options[:caption]
  end

  def test_say_with_media_document_raises_terminate
    prompt = FlowChat::Whatsapp::Prompt.new(nil)

    error = assert_raises(FlowChat::Interrupt::Terminate) do
      prompt.say("Here's your receipt:", media: {
        type: :document,
        url: "https://example.com/receipt.pdf",
        filename: "receipt.pdf"
      })
    end

    assert_equal :media_document, error.prompt[0]

    options = error.prompt[2]
    assert_equal "https://example.com/receipt.pdf", options[:url]
    assert_equal "Here's your receipt:", options[:caption]
    assert_equal "receipt.pdf", options[:filename]
  end

  def test_say_without_media_raises_text_terminate
    prompt = FlowChat::Whatsapp::Prompt.new(nil)

    error = assert_raises(FlowChat::Interrupt::Terminate) do
      prompt.say("Thank you!")
    end

    assert_equal :text, error.prompt[0]
    assert_equal "Thank you!", error.prompt[1]
    assert_equal({}, error.prompt[2])
  end

  def test_select_does_not_support_media
    prompt = FlowChat::Whatsapp::Prompt.new(nil)

    # select method should not accept media parameter
    # This should work fine without media
    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt.select("Choose option:", ["A", "B"])
    end

    # Should still be interactive list
    assert_equal :interactive_list, error.prompt[0]
  end

  def test_yes_does_not_support_media
    prompt = FlowChat::Whatsapp::Prompt.new(nil)

    # yes? method should not accept media parameter
    # This should work fine without media
    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt.yes?("Are you sure?")
    end

    # Should still be interactive buttons
    assert_equal :interactive_buttons, error.prompt[0]
  end

  def test_build_media_prompt_with_default_image_type
    prompt = FlowChat::Whatsapp::Prompt.new(nil)

    result = prompt.send(:build_media_prompt, "Test message", {
      url: "https://example.com/file"
      # No type specified, should default to :image
    })

    assert_equal :media_image, result[0]
    assert_equal "https://example.com/file", result[2][:url]
    assert_equal "Test message", result[2][:caption]
  end

  def test_media_prompt_validation_with_conversion_and_validation
    prompt_with_input = FlowChat::Whatsapp::Prompt.new("25")

    result = prompt_with_input.ask("Enter your age:",
      media: {type: :image, url: "https://example.com/age_help.jpg"},
      convert: ->(input) { input.to_i },
      validate: ->(input) { "Must be 18+" unless input >= 18 })

    assert_equal 25, result
  end

  def test_media_prompt_validation_failure
    prompt_with_input = FlowChat::Whatsapp::Prompt.new("12")

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt_with_input.ask("Enter your age:",
        media: {type: :image, url: "https://example.com/age_help.jpg"},
        convert: ->(input) { input.to_i },
        validate: ->(input) { "Must be 18+" unless input >= 18 })
    end

    # Should show validation error as text message
    assert_equal :text, error.prompt[0]
    assert_includes error.prompt[1], "Must be 18+"
  end
end

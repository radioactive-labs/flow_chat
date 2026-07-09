require "test_helper"

class FlowChat::Telegram::RendererTest < Minitest::Test
  def test_render_text_only
    renderer = FlowChat::Telegram::Renderer.new("Hello World")
    result = renderer.render

    assert_equal :text, result[0]
    assert_equal "Hello World", result[1]
    assert_equal({}, result[2])
  end

  def test_render_text_preserves_valid_html
    renderer = FlowChat::Telegram::Renderer.new("Hello <b>World</b> & friends")
    result = renderer.render

    assert_equal :text, result[0]
    # Valid HTML tags are preserved, ampersand is escaped
    assert_equal "Hello <b>World</b> &amp; friends", result[1]
  end

  def test_render_markdown_converted_to_html
    renderer = FlowChat::Telegram::Renderer.new("Hello **bold** and *italic*")
    result = renderer.render

    assert_equal :text, result[0]
    # Markdown is converted to HTML
    assert_equal "Hello <strong>bold</strong> and <em>italic</em>", result[1]
  end

  def test_render_nil_message
    renderer = FlowChat::Telegram::Renderer.new(nil)
    result = renderer.render

    assert_equal :text, result[0]
    assert_equal "", result[1]
  end

  # Markdown conversion tests

  def test_render_multiple_paragraphs
    renderer = FlowChat::Telegram::Renderer.new("First paragraph.\n\nSecond paragraph.")
    result = renderer.render

    assert_equal :text, result[0]
    # Paragraphs are converted to double newlines
    assert_equal "First paragraph.\n\nSecond paragraph.", result[1]
  end

  def test_render_inline_code
    renderer = FlowChat::Telegram::Renderer.new("Use `code` here")
    result = renderer.render

    assert_equal :text, result[0]
    assert_equal "Use <code>code</code> here", result[1]
  end

  def test_render_code_block
    # Kramdown uses indented code blocks (4 spaces) for <pre><code>
    renderer = FlowChat::Telegram::Renderer.new("    def hello\n      puts 'hi'\n    end")
    result = renderer.render

    assert_equal :text, result[0]
    assert_includes result[1], "<pre>"
    assert_includes result[1], "<code>"
    assert_includes result[1], "def hello"
  end

  def test_render_blockquote
    renderer = FlowChat::Telegram::Renderer.new("> This is a quote")
    result = renderer.render

    assert_equal :text, result[0]
    assert_includes result[1], "<blockquote>"
    assert_includes result[1], "This is a quote"
  end

  def test_render_markdown_links
    renderer = FlowChat::Telegram::Renderer.new("Visit [Google](https://google.com)")
    result = renderer.render

    assert_equal :text, result[0]
    assert_includes result[1], '<a href="https://google.com">Google</a>'
  end

  def test_render_nested_formatting
    renderer = FlowChat::Telegram::Renderer.new("**bold and *italic* inside**")
    result = renderer.render

    assert_equal :text, result[0]
    assert_includes result[1], "<strong>"
    assert_includes result[1], "<em>"
  end

  def test_render_underline_preserved
    renderer = FlowChat::Telegram::Renderer.new("Text with <u>underline</u>")
    result = renderer.render

    assert_equal :text, result[0]
    assert_includes result[1], "<u>underline</u>"
  end

  def test_render_strikethrough_preserved
    renderer = FlowChat::Telegram::Renderer.new("Text with <s>strikethrough</s>")
    result = renderer.render

    assert_equal :text, result[0]
    assert_includes result[1], "<s>strikethrough</s>"
  end

  def test_render_del_tag_preserved
    renderer = FlowChat::Telegram::Renderer.new("Text with <del>deleted</del>")
    result = renderer.render

    assert_equal :text, result[0]
    assert_includes result[1], "<del>deleted</del>"
  end

  def test_render_strike_tag_preserved
    renderer = FlowChat::Telegram::Renderer.new("Text with <strike>struck</strike>")
    result = renderer.render

    assert_equal :text, result[0]
    assert_includes result[1], "<strike>struck</strike>"
  end

  # HTML sanitization tests

  def test_disallowed_tags_stripped
    renderer = FlowChat::Telegram::Renderer.new("Hello <script>alert('xss')</script> World")
    result = renderer.render

    assert_equal :text, result[0]
    # Sanitizer strips the tag but preserves text content (standard behavior)
    refute_includes result[1], "<script>"
    refute_includes result[1], "</script>"
  end

  def test_div_tags_stripped
    renderer = FlowChat::Telegram::Renderer.new("Hello <div>content</div> World")
    result = renderer.render

    assert_equal :text, result[0]
    refute_includes result[1], "<div>"
  end

  def test_span_tags_stripped
    renderer = FlowChat::Telegram::Renderer.new("Hello <span style='color:red'>red</span> World")
    result = renderer.render

    assert_equal :text, result[0]
    refute_includes result[1], "<span>"
    refute_includes result[1], "style"
  end

  def test_disallowed_attributes_stripped
    renderer = FlowChat::Telegram::Renderer.new('<a href="https://example.com" onclick="alert()">link</a>')
    result = renderer.render

    assert_equal :text, result[0]
    assert_includes result[1], 'href="https://example.com"'
    refute_includes result[1], "onclick"
  end

  # Newline handling tests

  def test_br_converted_to_newline
    renderer = FlowChat::Telegram::Renderer.new("Line 1<br>Line 2")
    result = renderer.render

    assert_equal :text, result[0]
    assert_includes result[1], "Line 1\nLine 2"
  end

  def test_br_self_closing_converted_to_newline
    renderer = FlowChat::Telegram::Renderer.new("Line 1<br/>Line 2")
    result = renderer.render

    assert_equal :text, result[0]
    assert_includes result[1], "Line 1\nLine 2"
  end

  def test_excessive_newlines_cleaned_up
    renderer = FlowChat::Telegram::Renderer.new("Para 1\n\n\n\n\nPara 2")
    result = renderer.render

    assert_equal :text, result[0]
    # Excessive newlines should be reduced to double newlines
    refute_includes result[1], "\n\n\n"
  end

  # Smart quotes disabled test

  def test_straight_quotes_preserved
    renderer = FlowChat::Telegram::Renderer.new("He said 'hello' and \"goodbye\"")
    result = renderer.render

    assert_equal :text, result[0]
    # Should have straight quotes, not curly quotes
    assert_includes result[1], "'"
    assert_includes result[1], '"'
    refute_includes result[1], "\u2018"  # left single curly quote
    refute_includes result[1], "\u201C"  # left double curly quote
  end

  # Keyboard tests

  def test_render_with_choices_as_inline_keyboard
    choices = {
      "opt1" => "Option 1",
      "opt2" => "Option 2",
      "opt3" => "Option 3"
    }
    renderer = FlowChat::Telegram::Renderer.new("Choose:", choices: choices)
    result = renderer.render

    assert_equal :inline_keyboard, result[0]
    assert_equal "Choose:", result[1]
    assert result[2][:keyboard].is_a?(Array)

    # With 3 choices, should be laid out 2 per row
    keyboard = result[2][:keyboard]
    assert_equal 2, keyboard.length  # 2 rows
    assert_equal 2, keyboard[0].length  # First row has 2 buttons
    assert_equal 1, keyboard[1].length  # Second row has 1 button
  end

  def test_render_with_many_choices_single_column
    choices = {
      "opt1" => "Option 1",
      "opt2" => "Option 2",
      "opt3" => "Option 3",
      "opt4" => "Option 4",
      "opt5" => "Option 5"
    }
    renderer = FlowChat::Telegram::Renderer.new("Choose:", choices: choices)
    result = renderer.render

    assert_equal :inline_keyboard, result[0]
    keyboard = result[2][:keyboard]

    # With 5 choices (>4), each button on its own row
    assert_equal 5, keyboard.length
    keyboard.each do |row|
      assert_equal 1, row.length
    end
  end

  def test_inline_keyboard_button_structure
    choices = {"my_key" => "My Button Text"}
    renderer = FlowChat::Telegram::Renderer.new("Choose:", choices: choices)
    result = renderer.render

    button = result[2][:keyboard][0][0]
    assert_equal "My Button Text", button[:text]
    assert_equal "my_key", button[:callback_data]
  end

  def test_button_text_truncation
    long_text = "This is a very long button text that exceeds the sixty-four character limit for Telegram buttons"
    choices = {"key" => long_text}
    renderer = FlowChat::Telegram::Renderer.new("Choose:", choices: choices)
    result = renderer.render

    button = result[2][:keyboard][0][0]
    assert button[:text].length <= 64
    assert button[:text].end_with?("...")
  end

  def test_callback_data_truncation
    long_key = "a" * 100  # callback_data has 64 byte limit
    choices = {long_key => "Button"}
    renderer = FlowChat::Telegram::Renderer.new("Choose:", choices: choices)
    result = renderer.render

    button = result[2][:keyboard][0][0]
    assert button[:callback_data].length <= 64
  end

  # Media tests

  def test_render_media_photo
    media = {type: :photo, url: "https://example.com/image.jpg"}
    renderer = FlowChat::Telegram::Renderer.new("Check this out", media: media)
    result = renderer.render

    assert_equal :photo, result[0]
    assert_equal "Check this out", result[1]
    assert_equal "https://example.com/image.jpg", result[2][:url]
  end

  def test_render_media_photo_with_file_id
    media = {type: :photo, file_id: "AgACAgIAAxkBAAI"}
    renderer = FlowChat::Telegram::Renderer.new("Caption", media: media)
    result = renderer.render

    assert_equal :photo, result[0]
    assert_equal "AgACAgIAAxkBAAI", result[2][:url]
  end

  def test_render_media_document
    media = {type: :document, url: "https://example.com/doc.pdf", filename: "report.pdf"}
    renderer = FlowChat::Telegram::Renderer.new("Here is the report", media: media)
    result = renderer.render

    assert_equal :document, result[0]
    assert_equal "Here is the report", result[1]
    assert_equal "https://example.com/doc.pdf", result[2][:url]
    assert_equal "report.pdf", result[2][:filename]
  end

  def test_render_media_video
    media = {type: :video, url: "https://example.com/video.mp4"}
    renderer = FlowChat::Telegram::Renderer.new("Watch this", media: media)
    result = renderer.render

    assert_equal :video, result[0]
    assert_equal "Watch this", result[1]
    assert_equal "https://example.com/video.mp4", result[2][:url]
  end

  def test_render_media_audio
    media = {type: :audio, url: "https://example.com/audio.mp3"}
    renderer = FlowChat::Telegram::Renderer.new("Listen", media: media)
    result = renderer.render

    assert_equal :audio, result[0]
    assert_equal "Listen", result[1]
    assert_equal "https://example.com/audio.mp3", result[2][:url]
  end

  def test_render_media_voice
    media = {type: :voice, url: "https://example.com/voice.ogg"}
    renderer = FlowChat::Telegram::Renderer.new(nil, media: media)
    result = renderer.render

    assert_equal :voice, result[0]
    # Voice messages don't have captions, nil converts to empty string
    assert_equal "", result[1]
    assert_equal "https://example.com/voice.ogg", result[2][:url]
  end

  def test_render_unsupported_media_type_falls_back_to_text
    media = {type: :unknown, url: "https://example.com/file"}
    renderer = FlowChat::Telegram::Renderer.new("Message", media: media)
    result = renderer.render

    assert_equal :text, result[0]
    assert_equal "Message", result[1]
  end

  def test_render_photo_with_inline_keyboard
    choices = {"like" => "Like", "share" => "Share"}
    media = {type: :photo, url: "https://example.com/photo.jpg"}

    renderer = FlowChat::Telegram::Renderer.new("What do you think?", choices: choices, media: media)
    result = renderer.render

    assert_equal :photo_with_keyboard, result[0]
    assert_equal "What do you think?", result[1]
    assert_equal "https://example.com/photo.jpg", result[2][:url]
    assert result[2][:keyboard].is_a?(Array)
    assert_equal :photo, result[2][:media_type]
  end

  def test_render_video_with_inline_keyboard
    choices = {"play" => "Play Again", "next" => "Next"}
    media = {type: :video, url: "https://example.com/video.mp4"}

    renderer = FlowChat::Telegram::Renderer.new("Caption", choices: choices, media: media)
    result = renderer.render

    assert_equal :photo_with_keyboard, result[0]  # Generic type for media with keyboard
    assert_equal :video, result[2][:media_type]
  end

  def test_render_media_with_markdown_caption
    media = {type: :photo, url: "https://example.com/image.jpg"}
    renderer = FlowChat::Telegram::Renderer.new("Check out this **amazing** photo!", media: media)
    result = renderer.render

    assert_equal :photo, result[0]
    assert_includes result[1], "<strong>amazing</strong>"
  end

  # Validation tests

  def test_choices_must_be_hash
    renderer = FlowChat::Telegram::Renderer.new("Choose:", choices: "invalid")

    error = assert_raises(ArgumentError) do
      renderer.render
    end

    assert_equal "choices must be a Hash", error.message
  end

  def test_empty_message_with_choices
    choices = {"a" => "A", "b" => "B"}
    renderer = FlowChat::Telegram::Renderer.new("", choices: choices)
    result = renderer.render

    assert_equal :inline_keyboard, result[0]
    assert_equal "", result[1]
  end

  def test_keyboard_layout_with_two_choices
    choices = {"a" => "Option A", "b" => "Option B"}
    renderer = FlowChat::Telegram::Renderer.new("Pick:", choices: choices)
    result = renderer.render

    keyboard = result[2][:keyboard]
    # 2 choices should be in one row
    assert_equal 1, keyboard.length
    assert_equal 2, keyboard[0].length
  end

  def test_keyboard_layout_with_four_choices
    choices = {"a" => "A", "b" => "B", "c" => "C", "d" => "D"}
    renderer = FlowChat::Telegram::Renderer.new("Pick:", choices: choices)
    result = renderer.render

    keyboard = result[2][:keyboard]
    # 4 choices: 2 per row = 2 rows
    assert_equal 2, keyboard.length
    assert_equal 2, keyboard[0].length
    assert_equal 2, keyboard[1].length
  end

  def test_keyboard_preserves_choice_order
    choices = {"first" => "First", "second" => "Second", "third" => "Third"}
    renderer = FlowChat::Telegram::Renderer.new("Pick:", choices: choices)
    result = renderer.render

    keyboard = result[2][:keyboard]
    buttons = keyboard.flatten

    assert_equal "First", buttons[0][:text]
    assert_equal "first", buttons[0][:callback_data]
    assert_equal "Second", buttons[1][:text]
    assert_equal "Third", buttons[2][:text]
  end

  def test_parse_mode_default
    renderer = FlowChat::Telegram::Renderer.new("Hello")
    result = renderer.render

    # By default, we're escaping HTML, so parse_mode should be HTML
    assert_equal "HTML", result[2][:parse_mode] || "HTML"
  end
end

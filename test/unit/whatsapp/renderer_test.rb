require "test_helper"

class WhatsappRendererTest < Minitest::Test
  def test_render_text_only
    renderer = FlowChat::Whatsapp::Renderer.new("Hello World")
    result = renderer.render

    assert_equal [:text, "Hello World", {}], result
  end

  def test_render_with_choices_as_buttons
    # In the new architecture, middleware transforms choices before renderer sees them
    # Middleware converts {1 => "Option 1", 2 => "Option 2"} to {"Option 1" => "Option 1", "Option 2" => "Option 2"}
    # So renderer receives choices with generated IDs as keys
    choices = {
      "Option 1" => "Option 1",
      "Option 2" => "Option 2",
      "Option 3" => "Option 3"
    }
    renderer = FlowChat::Whatsapp::Renderer.new("Choose:", choices: choices)
    result = renderer.render

    # Renderer uses the keys (which are already WhatsApp-safe IDs) as button IDs
    expected_buttons = [
      {id: "Option 1", title: "Option 1"},
      {id: "Option 2", title: "Option 2"},
      {id: "Option 3", title: "Option 3"}
    ]

    assert_equal :interactive_buttons, result[0]
    assert_equal "Choose:", result[1]
    assert_equal expected_buttons, result[2][:buttons]

    # No mapping in renderer anymore - middleware handles mapping
    assert_nil result[2][:mapping]
  end

  def test_render_with_choices_as_list
    choices = ["Option 1", "Option 2", "Option 3", "Option 4", "Option 5"].map.with_index { |c, i| [i + 1, c] }.to_h
    renderer = FlowChat::Whatsapp::Renderer.new("Choose:", choices: choices)
    result = renderer.render

    assert_equal :interactive_list, result[0]
    assert_equal "Choose:", result[1]
    assert_equal 1, result[2][:sections].length
    assert_equal 5, result[2][:sections][0][:rows].length
  end

  def test_render_media_image
    media = {type: :image, url: "https://example.com/image.jpg"}
    renderer = FlowChat::Whatsapp::Renderer.new("Check this out", media: media)
    result = renderer.render

    assert_equal :media_image, result[0]
    assert_equal "", result[1]
    assert_equal "https://example.com/image.jpg", result[2][:url]
    assert_equal "Check this out", result[2][:caption]
  end

  def test_render_media_document_with_filename
    media = {type: :document, url: "https://example.com/doc.pdf", filename: "menu.pdf"}
    renderer = FlowChat::Whatsapp::Renderer.new("Menu", media: media)
    result = renderer.render

    assert_equal :media_document, result[0]
    assert_equal "", result[1]
    assert_equal "https://example.com/doc.pdf", result[2][:url]
    assert_equal "Menu", result[2][:caption]
    assert_equal "menu.pdf", result[2][:filename]
  end

  def test_render_media_with_buttons
    # Middleware would have transformed array choices to ID-based hash
    # e.g., ["Like", "Dislike", "Share"] -> {"Like" => "Like", "Dislike" => "Dislike", "Share" => "Share"}
    choices = {
      "Like" => "Like",
      "Dislike" => "Dislike",
      "Share" => "Share"
    }
    media = {type: :image, url: "https://example.com/photo.jpg"}

    renderer = FlowChat::Whatsapp::Renderer.new(
      "What do you think?",
      choices: choices,
      media: media
    )
    result = renderer.render

    # Renderer uses keys as IDs
    expected_buttons = [
      {id: "Like", title: "Like"},
      {id: "Dislike", title: "Dislike"},
      {id: "Share", title: "Share"}
    ]

    expected_header = {
      type: "image",
      image: {link: "https://example.com/photo.jpg"}
    }

    assert_equal :interactive_buttons, result[0]
    assert_equal "What do you think?", result[1]
    assert_equal expected_buttons, result[2][:buttons]
    assert_equal expected_header, result[2][:header]

    # No mapping in renderer anymore - middleware handles mapping
    assert_nil result[2][:mapping]
  end

  def test_media_header_types
    test_cases = [
      {
        media: {type: :image, url: "https://example.com/image.jpg"},
        expected_header: {type: "image", image: {link: "https://example.com/image.jpg"}}
      },
      {
        media: {type: :video, url: "https://example.com/video.mp4"},
        expected_header: {type: "video", video: {link: "https://example.com/video.mp4"}}
      },
      {
        media: {type: :document, url: "https://example.com/doc.pdf", filename: "test.pdf"},
        expected_header: {type: "document", document: {link: "https://example.com/doc.pdf", filename: "test.pdf"}}
      },
      {
        media: {type: :text, url: "Header Text"},
        expected_header: {type: "text", text: "Header Text"}
      }
    ]

    test_cases.each do |test_case|
      choices = ["Option 1", "Option 2"]
      renderer = FlowChat::Whatsapp::Renderer.new("Test", choices: choices, media: test_case[:media])
      result = renderer.render

      assert_equal :interactive_buttons, result[0]
      assert_equal test_case[:expected_header], result[2][:header], "Failed for media type: #{test_case[:media][:type]}"
    end
  end

  def test_unsupported_header_media_type_raises_error
    media = {type: :audio, url: "https://example.com/audio.mp3"}
    choices = ["Option 1", "Option 2"]

    renderer = FlowChat::Whatsapp::Renderer.new("Test", choices: choices, media: media)

    error = assert_raises(ArgumentError) do
      renderer.render
    end

    assert_includes error.message, "Unsupported header media type: audio"
    assert_includes error.message, "Supported types for button headers: image, video, document, text"
  end

  def test_hash_choices_with_media
    # Middleware would have transformed {"option1" => "First Option"}
    # to {"First Option" => "First Option"}
    choices = {
      "First Option" => "First Option",
      "Second Option" => "Second Option"
    }
    media = {type: :image, url: "https://example.com/image.jpg"}

    renderer = FlowChat::Whatsapp::Renderer.new("Choose", choices: choices, media: media)
    result = renderer.render

    # Renderer uses keys as IDs
    expected_buttons = [
      {id: "First Option", title: "First Option"},
      {id: "Second Option", title: "Second Option"}
    ]

    assert_equal :interactive_buttons, result[0]
    assert_equal expected_buttons, result[2][:buttons]
    assert result[2][:header].present?

    # No mapping in renderer anymore - middleware handles mapping
    assert_nil result[2][:mapping]
  end

  def test_button_title_truncation
    long_title = "This is a very long option title that exceeds twenty characters"
    choices = [long_title].map.with_index { |c, i| [i + 1, c] }.to_h

    renderer = FlowChat::Whatsapp::Renderer.new("Choose", choices: choices)
    result = renderer.render

    button = result[2][:buttons][0]
    assert_equal "This is a very lo...", button[:title]
    assert button[:title].length <= 20
  end

  def test_sticker_media_without_caption
    media = {type: :sticker, url: "https://example.com/sticker.webp"}
    renderer = FlowChat::Whatsapp::Renderer.new("Check this sticker", media: media)
    result = renderer.render

    assert_equal :media_sticker, result[0]
    assert_equal "", result[1]
    assert_equal "https://example.com/sticker.webp", result[2][:url]
    refute result[2].key?(:caption) # Stickers don't support captions
  end

  def test_large_list_pagination
    choices = (1..25).map { |i| [i, "Option #{i}"] }.to_h
    renderer = FlowChat::Whatsapp::Renderer.new("Choose", choices: choices)
    result = renderer.render

    assert_equal :interactive_list, result[0]
    assert_equal 3, result[2][:sections].length # Should be split into 3 sections (10+10+5)
    assert_equal "1-10", result[2][:sections][0][:title]
    assert_equal "11-20", result[2][:sections][1][:title]
    assert_equal "21-25", result[2][:sections][2][:title]
  end

  def test_list_item_description_for_long_titles
    long_title = "This is a very long option title that should be truncated in the title but appear fully in description"
    choices = [long_title, "Short", "Another option", "Fourth option"].map.with_index { |c, i| [i + 1, c] }.to_h # >3 choices to force list

    renderer = FlowChat::Whatsapp::Renderer.new("Choose", choices: choices)
    result = renderer.render

    # Should be a list since we have >3 choices
    assert_equal :interactive_list, result[0]
    assert result[2][:sections].present?, "Sections should be present"
    assert result[2][:sections][0][:rows].present?, "Rows should be present"

    item = result[2][:sections][0][:rows][0] # First item with long title
    assert item.present?, "Item should be present"

    assert_equal "This is a very long o...", item[:title] # Truncated at 24 chars
    if item[:description]
      # Description is truncated at 72 chars, so check for beginning portion
      assert_includes item[:description], "This is a very long option title that should be truncated"
    end
  end

  def test_invalid_choices_type_raises_error
    renderer = FlowChat::Whatsapp::Renderer.new("Choose", choices: "invalid")

    error = assert_raises(ArgumentError) do
      renderer.render
    end

    assert_equal "choices must be a Hash", error.message
  end

  def test_media_requires_url
    media = {type: :image, path: "/local/image.jpg"}
    renderer = FlowChat::Whatsapp::Renderer.new("Local image", media: media)
    result = renderer.render

    assert_nil result[2][:url]
  end

  def test_unsupported_media_type_raises_error
    media = {type: :unsupported, url: "https://example.com/file"}
    renderer = FlowChat::Whatsapp::Renderer.new("Test", media: media)

    error = assert_raises(ArgumentError) do
      renderer.render
    end

    assert_equal "Unsupported media type: unsupported", error.message
  end

  # Markdown formatting tests

  def test_render_markdown_bold
    renderer = FlowChat::Whatsapp::Renderer.new("Hello **bold** world")
    result = renderer.render

    assert_equal :text, result[0]
    assert_equal "Hello *bold* world", result[1]
  end

  def test_render_markdown_italic
    renderer = FlowChat::Whatsapp::Renderer.new("Hello *italic* world")
    result = renderer.render

    assert_equal :text, result[0]
    assert_equal "Hello _italic_ world", result[1]
  end

  def test_render_markdown_strikethrough
    renderer = FlowChat::Whatsapp::Renderer.new("Hello ~~strikethrough~~ world")
    result = renderer.render

    assert_equal :text, result[0]
    assert_equal "Hello ~strikethrough~ world", result[1]
  end

  def test_render_markdown_inline_code
    renderer = FlowChat::Whatsapp::Renderer.new("Use `code` here")
    result = renderer.render

    assert_equal :text, result[0]
    assert_equal "Use `code` here", result[1]
  end

  def test_render_markdown_code_block
    renderer = FlowChat::Whatsapp::Renderer.new("```\ndef hello\n  puts 'hi'\nend\n```")
    result = renderer.render

    assert_equal :text, result[0]
    assert_includes result[1], "```"
    assert_includes result[1], "def hello"
  end

  def test_render_markdown_link
    renderer = FlowChat::Whatsapp::Renderer.new("Visit [Google](https://google.com)")
    result = renderer.render

    assert_equal :text, result[0]
    # Links become "text (url)" format
    assert_includes result[1], "Google"
    assert_includes result[1], "https://google.com"
  end

  def test_render_markdown_link_same_text_as_url
    renderer = FlowChat::Whatsapp::Renderer.new("Visit [https://google.com](https://google.com)")
    result = renderer.render

    assert_equal :text, result[0]
    # When text equals URL, just show URL once
    assert_equal "Visit https://google.com", result[1]
  end

  def test_render_markdown_unordered_list
    renderer = FlowChat::Whatsapp::Renderer.new("Items:\n\n* First\n* Second\n* Third")
    result = renderer.render

    assert_equal :text, result[0]
    assert_includes result[1], "• First"
    assert_includes result[1], "• Second"
    assert_includes result[1], "• Third"
  end

  def test_render_markdown_ordered_list
    renderer = FlowChat::Whatsapp::Renderer.new("Steps:\n\n1. First\n2. Second\n3. Third")
    result = renderer.render

    assert_equal :text, result[0]
    assert_includes result[1], "1. First"
    assert_includes result[1], "2. Second"
    assert_includes result[1], "3. Third"
  end

  def test_render_markdown_blockquote
    renderer = FlowChat::Whatsapp::Renderer.new("> This is a quote")
    result = renderer.render

    assert_equal :text, result[0]
    assert_includes result[1], "> This is a quote"
  end

  def test_render_markdown_heading_degrades_to_bold
    renderer = FlowChat::Whatsapp::Renderer.new("# Main Heading")
    result = renderer.render

    assert_equal :text, result[0]
    # Headings aren't supported, but the text should still be present
    assert_includes result[1], "Main Heading"
  end

  def test_render_markdown_nested_formatting
    renderer = FlowChat::Whatsapp::Renderer.new("This is **bold and *italic* inside**")
    result = renderer.render

    assert_equal :text, result[0]
    assert_includes result[1], "*"
    assert_includes result[1], "_"
  end

  def test_render_markdown_multiple_paragraphs
    renderer = FlowChat::Whatsapp::Renderer.new("First paragraph.\n\nSecond paragraph.")
    result = renderer.render

    assert_equal :text, result[0]
    assert_includes result[1], "First paragraph."
    assert_includes result[1], "Second paragraph."
    # Should have newlines between paragraphs
    assert_includes result[1], "\n"
  end

  def test_render_nil_message
    renderer = FlowChat::Whatsapp::Renderer.new(nil)
    result = renderer.render

    assert_equal :text, result[0]
    assert_equal "", result[1]
  end

  def test_render_plain_text_unchanged
    renderer = FlowChat::Whatsapp::Renderer.new("Hello World")
    result = renderer.render

    assert_equal :text, result[0]
    assert_equal "Hello World", result[1]
  end

  def test_render_html_entities_decoded
    renderer = FlowChat::Whatsapp::Renderer.new("Tom & Jerry")
    result = renderer.render

    assert_equal :text, result[0]
    assert_equal "Tom & Jerry", result[1]
  end

  def test_render_straight_quotes_preserved
    renderer = FlowChat::Whatsapp::Renderer.new("He said 'hello' and \"goodbye\"")
    result = renderer.render

    assert_equal :text, result[0]
    assert_includes result[1], "'"
    assert_includes result[1], '"'
    # Should NOT have curly quotes
    refute_includes result[1], "\u2018"
    refute_includes result[1], "\u201C"
  end

  # Markdown in media captions

  def test_render_media_caption_with_markdown
    media = {type: :image, url: "https://example.com/image.jpg"}
    renderer = FlowChat::Whatsapp::Renderer.new("Check out this **amazing** photo!", media: media)
    result = renderer.render

    assert_equal :media_image, result[0]
    assert_equal "Check out this *amazing* photo!", result[2][:caption]
  end

  # Markdown in interactive messages

  def test_render_interactive_buttons_with_markdown
    choices = {"opt1" => "Option 1", "opt2" => "Option 2"}
    renderer = FlowChat::Whatsapp::Renderer.new("Choose **wisely**:", choices: choices)
    result = renderer.render

    assert_equal :interactive_buttons, result[0]
    assert_equal "Choose *wisely*:", result[1]
  end

  def test_render_interactive_list_with_markdown
    choices = (1..5).map { |i| [i, "Option #{i}"] }.to_h
    renderer = FlowChat::Whatsapp::Renderer.new("Select an *option*:", choices: choices)
    result = renderer.render

    assert_equal :interactive_list, result[0]
    assert_equal "Select an _option_:", result[1]
  end

  # Edge case tests

  def test_render_empty_string
    renderer = FlowChat::Whatsapp::Renderer.new("")
    result = renderer.render

    assert_equal :text, result[0]
    assert_equal "", result[1]
  end

  def test_render_code_block_with_language
    renderer = FlowChat::Whatsapp::Renderer.new("```ruby\ndef hello\n  puts 'hi'\nend\n```")
    result = renderer.render

    assert_equal :text, result[0]
    assert_includes result[1], "```"
    assert_includes result[1], "def hello"
    assert_includes result[1], "puts 'hi'"
  end

  def test_render_multiple_code_blocks
    input = "First:\n```\ncode1\n```\n\nSecond:\n```\ncode2\n```"
    renderer = FlowChat::Whatsapp::Renderer.new(input)
    result = renderer.render

    assert_equal :text, result[0]
    assert_includes result[1], "code1"
    assert_includes result[1], "code2"
  end

  def test_render_horizontal_rule
    renderer = FlowChat::Whatsapp::Renderer.new("Above\n\n---\n\nBelow")
    result = renderer.render

    assert_equal :text, result[0]
    assert_includes result[1], "Above"
    assert_includes result[1], "Below"
  end

  def test_render_nested_list
    input = "List:\n\n* Item 1\n  * Nested 1\n  * Nested 2\n* Item 2"
    renderer = FlowChat::Whatsapp::Renderer.new(input)
    result = renderer.render

    assert_equal :text, result[0]
    assert_includes result[1], "Item 1"
    assert_includes result[1], "Nested 1"
    assert_includes result[1], "Item 2"
  end

  def test_render_link_with_special_characters
    renderer = FlowChat::Whatsapp::Renderer.new("Check [this link](https://example.com/path?foo=bar&baz=qux)")
    result = renderer.render

    assert_equal :text, result[0]
    assert_includes result[1], "this link"
    assert_includes result[1], "https://example.com/path?foo=bar&baz=qux"
  end

  def test_render_media_without_caption
    media = {type: :image, url: "https://example.com/image.jpg"}
    renderer = FlowChat::Whatsapp::Renderer.new(nil, media: media)
    result = renderer.render

    assert_equal :media_image, result[0]
    assert_equal "", result[1]
    assert_nil result[2][:caption]
  end

  def test_render_media_with_blank_caption
    media = {type: :image, url: "https://example.com/image.jpg"}
    renderer = FlowChat::Whatsapp::Renderer.new("", media: media)
    result = renderer.render

    assert_equal :media_image, result[0]
    assert_nil result[2][:caption]
  end

  def test_render_unclosed_bold
    renderer = FlowChat::Whatsapp::Renderer.new("Hello **unclosed bold")
    result = renderer.render

    assert_equal :text, result[0]
    # Should not crash, text should be present
    assert_includes result[1], "Hello"
    assert_includes result[1], "unclosed bold"
  end

  def test_render_unclosed_code_block
    renderer = FlowChat::Whatsapp::Renderer.new("```\ncode without closing")
    result = renderer.render

    assert_equal :text, result[0]
    # Should not crash, content should be present
    assert_includes result[1], "code without closing"
  end

  def test_render_mixed_formatting
    input = "**Bold** and *italic* and `code` and ~~strike~~"
    renderer = FlowChat::Whatsapp::Renderer.new(input)
    result = renderer.render

    assert_equal :text, result[0]
    assert_includes result[1], "*Bold*"
    assert_includes result[1], "_italic_"
    assert_includes result[1], "`code`"
    assert_includes result[1], "~strike~"
  end

  def test_render_special_characters_not_markdown
    renderer = FlowChat::Whatsapp::Renderer.new("Price: $100 (50% off)")
    result = renderer.render

    assert_equal :text, result[0]
    assert_equal "Price: $100 (50% off)", result[1]
  end

  def test_render_multiline_blockquote
    renderer = FlowChat::Whatsapp::Renderer.new("> Line 1\n> Line 2\n> Line 3")
    result = renderer.render

    assert_equal :text, result[0]
    assert_includes result[1], "> Line 1"
    assert_includes result[1], "> Line 2"
    assert_includes result[1], "> Line 3"
  end

  def test_render_whitespace_only
    renderer = FlowChat::Whatsapp::Renderer.new("   \n\n   ")
    result = renderer.render

    assert_equal :text, result[0]
    assert_equal "", result[1]
  end

  def test_render_combined_bold_and_italic
    renderer = FlowChat::Whatsapp::Renderer.new("This is ***bold and italic***")
    result = renderer.render

    assert_equal :text, result[0]
    # kramdown treats *** as bold+italic
    assert_includes result[1], "*"
    assert_includes result[1], "_"
  end
end

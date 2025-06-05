require "test_helper"

class WhatsappRendererTest < Minitest::Test
  def test_render_text_only
    renderer = FlowChat::Whatsapp::Renderer.new("Hello World")
    result = renderer.render

    assert_equal [:text, "Hello World", {}], result
  end

  def test_render_with_choices_as_buttons
    choices = ["Option 1", "Option 2", "Option 3"].map.with_index { |c, i| [i + 1, c] }.to_h
    renderer = FlowChat::Whatsapp::Renderer.new("Choose:", choices: choices)
    result = renderer.render

    expected_buttons = [
      {id: "1", title: "Option 1"},
      {id: "2", title: "Option 2"},
      {id: "3", title: "Option 3"}
    ]

    assert_equal :interactive_buttons, result[0]
    assert_equal "Choose:", result[1]
    assert_equal expected_buttons, result[2][:buttons]
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
    choices = ["Like", "Dislike", "Share"]
    media = {type: :image, url: "https://example.com/photo.jpg"}
    
    renderer = FlowChat::Whatsapp::Renderer.new(
      "What do you think?",
      choices: choices,
      media: media
    )
    result = renderer.render

    expected_buttons = [
      {id: "0", title: "Like"},
      {id: "1", title: "Dislike"},
      {id: "2", title: "Share"}
    ]

    expected_header = {
      type: "image",
      image: {link: "https://example.com/photo.jpg"}
    }

    assert_equal :interactive_buttons, result[0]
    assert_equal "What do you think?", result[1]
    assert_equal expected_buttons, result[2][:buttons]
    assert_equal expected_header, result[2][:header]
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
    choices = {"option1" => "First Option", "option2" => "Second Option"}
    media = {type: :image, url: "https://example.com/image.jpg"}
    
    renderer = FlowChat::Whatsapp::Renderer.new("Choose", choices: choices, media: media)
    result = renderer.render

    expected_buttons = [
      {id: "option1", title: "First Option"},
      {id: "option2", title: "Second Option"}
    ]

    assert_equal :interactive_buttons, result[0]
    assert_equal expected_buttons, result[2][:buttons]
    assert result[2][:header].present?
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


  def test_media_uses_path_fallback
    media = {type: :image, path: "/local/image.jpg"}
    renderer = FlowChat::Whatsapp::Renderer.new("Local image", media: media)
    result = renderer.render

    assert_equal "/local/image.jpg", result[2][:url]
  end

  def test_unsupported_media_type_raises_error
    media = {type: :unsupported, url: "https://example.com/file"}
    renderer = FlowChat::Whatsapp::Renderer.new("Test", media: media)
    
    error = assert_raises(ArgumentError) do
      renderer.render
    end
    
    assert_equal "Unsupported media type: unsupported", error.message
  end
end 
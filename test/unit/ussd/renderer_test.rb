require "test_helper"

class UssdRendererTest < Minitest::Test
  def test_render_text_only
    renderer = FlowChat::Ussd::Renderer.new("Hello World")
    result = renderer.render

    assert_equal "Hello World", result
  end

  def test_render_with_choices_only
    choices = {"1" => "Option 1", "2" => "Option 2"}
    renderer = FlowChat::Ussd::Renderer.new("Choose:", choices: choices)
    result = renderer.render

    expected = "Choose:\n\n1. Option 1\n2. Option 2"
    assert_equal expected, result
  end

  def test_render_with_media_only
    media = {type: :image, url: "https://example.com/image.jpg"}
    renderer = FlowChat::Ussd::Renderer.new("Check this out:", media: media)
    result = renderer.render

    expected = "📷 Image: https://example.com/image.jpg\n\nCheck this out:"
    assert_equal expected, result
  end

  def test_render_with_media_and_choices_media_first
    choices = {"1" => "Like it", "2" => "Don't like it"}
    media = {type: :image, url: "https://example.com/photo.jpg"}
    
    renderer = FlowChat::Ussd::Renderer.new(
      "What do you think?",
      choices: choices,
      media: media
    )
    result = renderer.render

    expected = "📷 Image: https://example.com/photo.jpg\n\nWhat do you think?\n\n1. Like it\n2. Don't like it"
    assert_equal expected, result
  end

  def test_media_types_render_correctly
    test_cases = [
      {type: :image, url: "https://example.com/image.jpg", expected: "📷 Image: https://example.com/image.jpg"},
      {type: :document, url: "https://example.com/doc.pdf", expected: "📄 Document: https://example.com/doc.pdf"},
      {type: :audio, url: "https://example.com/audio.mp3", expected: "🎵 Audio: https://example.com/audio.mp3"},
      {type: :video, url: "https://example.com/video.mp4", expected: "🎥 Video: https://example.com/video.mp4"},
      {type: :sticker, url: "https://example.com/sticker.webp", expected: "😊 Sticker: https://example.com/sticker.webp"},
      {type: :unknown, url: "https://example.com/file.xyz", expected: "📎 Media: https://example.com/file.xyz"}
    ]

    test_cases.each do |test_case|
      renderer = FlowChat::Ussd::Renderer.new("Test:", media: test_case)
      result = renderer.render

      expected = "#{test_case[:expected]}\n\nTest:"
      assert_equal expected, result, "Failed for media type: #{test_case[:type]}"
    end
  end

  def test_media_uses_path_when_url_not_present
    media = {type: :image, path: "/local/image.jpg"}
    renderer = FlowChat::Ussd::Renderer.new("Local file:", media: media)
    result = renderer.render

    expected = "📷 Image: /local/image.jpg\n\nLocal file:"
    assert_equal expected, result
  end

  def test_media_defaults_to_image_type
    media = {url: "https://example.com/unknown"}
    renderer = FlowChat::Ussd::Renderer.new("Unknown type:", media: media)
    result = renderer.render

    expected = "📷 Image: https://example.com/unknown\n\nUnknown type:"
    assert_equal expected, result
  end

  def test_empty_choices_not_rendered
    renderer = FlowChat::Ussd::Renderer.new("Test", choices: {})
    result = renderer.render

    assert_equal "Test", result
  end

  def test_nil_media_not_rendered
    renderer = FlowChat::Ussd::Renderer.new("Test", media: nil)
    result = renderer.render

    assert_equal "Test", result
  end

  def test_complex_scenario_with_multiple_choices_and_media
    choices = (1..5).to_h { |i| [i.to_s, "Option #{i}"] }
    media = {type: :document, url: "https://example.com/menu.pdf"}
    
    renderer = FlowChat::Ussd::Renderer.new(
      "Select from menu:",
      choices: choices,
      media: media
    )
    result = renderer.render

    # Verify structure: message, media, choices (in that order)
    lines = result.split("\n")
    
    assert_equal "📄 Document: https://example.com/menu.pdf", lines[0]
    assert_equal "", lines[1] # blank line
    assert_equal "", lines[3] # blank line
    assert_equal "Select from menu:", lines[2]
    assert_equal "1. Option 1", lines[4]
    assert_equal "2. Option 2", lines[5]
    assert_equal "3. Option 3", lines[6]
    assert_equal "4. Option 4", lines[7]
    assert_equal "5. Option 5", lines[8]
  end
end 
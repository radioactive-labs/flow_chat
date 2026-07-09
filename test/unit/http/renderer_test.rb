require "test_helper"

class HttpRendererTest < Minitest::Test
  def test_renders_simple_message
    renderer = FlowChat::Http::Renderer.new("Hello, World!")
    result = renderer.render

    assert_equal "Hello, World!", result[:message]
    assert_nil result[:choices]
    assert_nil result[:media]
  end

  def test_renders_message_with_choices
    choices = {"1" => "Option 1", "2" => "Option 2"}
    renderer = FlowChat::Http::Renderer.new("Choose an option:", choices: choices)
    result = renderer.render

    assert_equal "Choose an option:", result[:message]
    assert_equal 2, result[:choices].size
    assert_equal "1", result[:choices][0][:key]
    assert_equal "Option 1", result[:choices][0][:value]
    assert_equal "2", result[:choices][1][:key]
    assert_equal "Option 2", result[:choices][1][:value]
  end

  def test_renders_message_with_media
    media = {url: "https://example.com/image.jpg", type: :image, caption: "Test image"}
    renderer = FlowChat::Http::Renderer.new("Check this out:", media: media)
    result = renderer.render

    assert_equal "Check this out:", result[:message]
    assert_equal "https://example.com/image.jpg", result[:media][:url]
    assert_equal :image, result[:media][:type]
    assert_equal "Test image", result[:media][:caption]
  end

  def test_renders_message_with_media_path
    media = {path: "/local/image.jpg", type: :image}
    renderer = FlowChat::Http::Renderer.new("Local image:", media: media)
    result = renderer.render

    assert_equal "Local image:", result[:message]
    assert_nil result[:media][:url]
    assert_equal :image, result[:media][:type]
    assert_nil result[:media][:caption]
  end

  def test_renders_message_with_media_defaults
    media = {url: "https://example.com/file.pdf"}
    renderer = FlowChat::Http::Renderer.new("Document:", media: media)
    result = renderer.render

    assert_equal "Document:", result[:message]
    assert_equal "https://example.com/file.pdf", result[:media][:url]
    assert_equal :image, result[:media][:type]  # Default type
  end

  def test_renders_complete_response
    choices = {"yes" => "Yes", "no" => "No"}
    media = {url: "https://example.com/image.jpg", type: :image}

    renderer = FlowChat::Http::Renderer.new(
      "Do you like this image?",
      choices: choices,
      media: media
    )
    result = renderer.render

    assert_equal "Do you like this image?", result[:message]
    assert_equal 2, result[:choices].size
    assert_equal "https://example.com/image.jpg", result[:media][:url]
  end

  def test_compact_removes_nil_values
    renderer = FlowChat::Http::Renderer.new("Simple message")
    result = renderer.render

    refute result.key?(:choices)
    refute result.key?(:media)
    assert result.key?(:message)
  end

  def test_format_choices_with_empty_choices
    renderer = FlowChat::Http::Renderer.new("Message")
    formatted = renderer.send(:format_choices)

    assert_nil formatted
  end

  def test_format_media_with_empty_media
    renderer = FlowChat::Http::Renderer.new("Message")
    formatted = renderer.send(:format_media)

    assert_nil formatted
  end
end

require "test_helper"

class FlowChat::Intercom::RendererTest < Minitest::Test
  def test_initialize_with_message_only
    message = "Hello, how can I help you?"
    renderer = FlowChat::Intercom::Renderer.new(message)

    assert_equal message, renderer.message
    assert_nil renderer.choices
    assert_nil renderer.media
  end

  def test_initialize_with_message_and_choices
    message = "Please select an option:"
    choices = {"1" => "Option 1", "2" => "Option 2"}
    renderer = FlowChat::Intercom::Renderer.new(message, choices: choices)

    assert_equal message, renderer.message
    assert_equal choices, renderer.choices
    assert_nil renderer.media
  end

  def test_initialize_with_all_parameters
    message = "Please select an option:"
    choices = {"1" => "Option 1", "2" => "Option 2"}
    media = {type: "image", url: "https://example.com/image.jpg"}
    renderer = FlowChat::Intercom::Renderer.new(message, choices: choices, media: media)

    assert_equal message, renderer.message
    assert_equal choices, renderer.choices
    assert_equal media, renderer.media
  end

  def test_render_text_message_no_choices
    message = "Hello, how can I help you today?"
    renderer = FlowChat::Intercom::Renderer.new(message)

    result = renderer.render

    # Messages are converted to HTML
    assert_equal [:text, "<p>Hello, how can I help you today?</p>", {}], result
  end

  def test_render_text_message_with_media_no_choices
    message = "Check out this image:"
    media = {type: "image", url: "https://example.com/image.jpg"}
    renderer = FlowChat::Intercom::Renderer.new(message, media: media)

    result = renderer.render

    assert_equal [:text, "<p>Check out this image:</p>", {}], result
  end

  def test_render_selection_message_with_choices
    message = "Please choose an option:"
    choices = {"billing" => "Billing Questions", "support" => "Technical Support"}
    renderer = FlowChat::Intercom::Renderer.new(message, choices: choices)

    result = renderer.render

    # Kramdown converts to HTML with paragraphs
    assert_equal :text, result[0]
    assert_includes result[1], "<p>Please choose an option:</p>"
    assert_includes result[1], "1. Billing Questions"
    assert_includes result[1], "2. Technical Support"
    assert_includes result[1], "Reply with the number of your choice."
    assert_equal({choices: choices}, result[2])
  end

  def test_render_selection_message_empty_message
    message = ""
    choices = {"yes" => "Yes", "no" => "No"}
    renderer = FlowChat::Intercom::Renderer.new(message, choices: choices)

    result = renderer.render

    assert_equal :text, result[0]
    assert_includes result[1], "1. Yes"
    assert_includes result[1], "2. No"
    assert_includes result[1], "Reply with the number of your choice."
    assert_equal({choices: choices}, result[2])
  end

  def test_render_selection_message_nil_message
    message = nil
    choices = {"option1" => "First Option", "option2" => "Second Option"}
    renderer = FlowChat::Intercom::Renderer.new(message, choices: choices)

    result = renderer.render

    assert_equal :text, result[0]
    assert_includes result[1], "1. First Option"
    assert_includes result[1], "2. Second Option"
    assert_equal({choices: choices}, result[2])
  end

  def test_render_selection_message_single_choice
    message = "Do you want to continue?"
    choices = {"continue" => "Yes, continue"}
    renderer = FlowChat::Intercom::Renderer.new(message, choices: choices)

    result = renderer.render

    assert_equal :text, result[0]
    assert_includes result[1], "Do you want to continue?"
    assert_includes result[1], "1. Yes, continue"
    assert_equal({choices: choices}, result[2])
  end

  def test_render_selection_message_multiple_choices
    message = "Select your department:"
    choices = {
      "sales" => "Sales Department",
      "support" => "Customer Support",
      "billing" => "Billing Department",
      "general" => "General Inquiries"
    }
    renderer = FlowChat::Intercom::Renderer.new(message, choices: choices)

    result = renderer.render

    assert_equal :text, result[0]
    assert_includes result[1], "Select your department:"
    assert_includes result[1], "1. Sales Department"
    assert_includes result[1], "2. Customer Support"
    assert_includes result[1], "3. Billing Department"
    assert_includes result[1], "4. General Inquiries"
    assert_equal({choices: choices}, result[2])
  end

  def test_render_selection_message_with_media
    message = "Based on the image above, what would you like to do?"
    choices = {"buy" => "Buy Now", "info" => "Get More Info"}
    media = {type: "image", url: "https://example.com/product.jpg"}
    renderer = FlowChat::Intercom::Renderer.new(message, choices: choices, media: media)

    result = renderer.render

    assert_equal :text, result[0]
    assert_includes result[1], "Based on the image above"
    assert_includes result[1], "1. Buy Now"
    assert_includes result[1], "2. Get More Info"
    assert_equal({choices: choices}, result[2])
  end

  def test_render_selection_message_preserves_choice_order
    message = "Select priority level:"
    choices = {"high" => "High Priority", "medium" => "Medium Priority", "low" => "Low Priority"}
    renderer = FlowChat::Intercom::Renderer.new(message, choices: choices)

    result = renderer.render

    # Ruby hashes maintain insertion order as of Ruby 1.9+
    assert_equal :text, result[0]
    assert_includes result[1], "1. High Priority"
    assert_includes result[1], "2. Medium Priority"
    assert_includes result[1], "3. Low Priority"
    assert_equal({choices: choices}, result[2])
  end

  def test_render_selection_message_with_special_characters
    message = "What's your issue?"
    choices = {
      "password" => "I can't access my account",
      "billing" => "Billing & payment issues",
      "bug" => "Found a bug/error"
    }
    renderer = FlowChat::Intercom::Renderer.new(message, choices: choices)

    result = renderer.render

    assert_equal :text, result[0]
    # Note: & gets escaped to &amp; in HTML, apostrophes remain straight quotes
    assert_includes result[1], "your issue?"
    assert_includes result[1], "access my account"
    assert_includes result[1], "&amp;"  # & is escaped
    assert_equal({choices: choices}, result[2])
  end

  def test_render_selection_message_invalid_choices_raises_error
    message = "Please choose:"
    choices = ["Option 1", "Option 2"]  # Array instead of Hash
    renderer = FlowChat::Intercom::Renderer.new(message, choices: choices)

    assert_raises(ArgumentError, "choices must be a Hash") do
      renderer.render
    end
  end

  def test_render_selection_message_empty_choices_hash
    message = "Please choose:"
    choices = {}
    renderer = FlowChat::Intercom::Renderer.new(message, choices: choices)

    result = renderer.render

    assert_equal :text, result[0]
    assert_includes result[1], "Please choose:"
    assert_includes result[1], "Reply with the number of your choice."
    assert_equal({choices: choices}, result[2])
  end

  def test_render_returns_array_with_three_elements
    renderer = FlowChat::Intercom::Renderer.new("Test message")
    result = renderer.render

    assert_instance_of Array, result
    assert_equal 3, result.length
    assert_equal :text, result[0]
    assert_instance_of String, result[1]
    assert_instance_of Hash, result[2]
  end

  def test_render_choices_preserved_in_options
    message = "Choose:"
    choices = {"a" => "Option A", "b" => "Option B"}
    renderer = FlowChat::Intercom::Renderer.new(message, choices: choices)

    result = renderer.render

    assert_equal choices, result[2][:choices]
  end

  def test_render_text_message_options_empty_hash
    message = "Simple text message"
    renderer = FlowChat::Intercom::Renderer.new(message)

    result = renderer.render

    assert_equal({}, result[2])
  end

  # Markdown conversion tests

  def test_render_markdown_bold_converted_to_html
    renderer = FlowChat::Intercom::Renderer.new("Hello **bold** text")
    result = renderer.render

    assert_equal :text, result[0]
    assert_includes result[1], "<strong>bold</strong>"
  end

  def test_render_markdown_italic_converted_to_html
    renderer = FlowChat::Intercom::Renderer.new("Hello *italic* text")
    result = renderer.render

    assert_equal :text, result[0]
    assert_includes result[1], "<em>italic</em>"
  end

  def test_render_markdown_links
    renderer = FlowChat::Intercom::Renderer.new("Visit [our site](https://example.com)")
    result = renderer.render

    assert_equal :text, result[0]
    assert_includes result[1], '<a href="https://example.com">our site</a>'
  end

  def test_render_markdown_unordered_list
    renderer = FlowChat::Intercom::Renderer.new("Items:\n\n* First\n* Second")
    result = renderer.render

    assert_equal :text, result[0]
    assert_includes result[1], "<ul>"
    assert_includes result[1], "<li>First</li>"
    assert_includes result[1], "<li>Second</li>"
  end

  def test_render_markdown_ordered_list
    renderer = FlowChat::Intercom::Renderer.new("Steps:\n\n1. First\n2. Second")
    result = renderer.render

    assert_equal :text, result[0]
    assert_includes result[1], "<ol>"
    assert_includes result[1], "<li>First</li>"
    assert_includes result[1], "<li>Second</li>"
  end

  def test_render_markdown_headings
    renderer = FlowChat::Intercom::Renderer.new("# Main Title\n\n## Subtitle")
    result = renderer.render

    assert_equal :text, result[0]
    assert_includes result[1], "<h1"
    assert_includes result[1], "Main Title"
    assert_includes result[1], "<h2"
    assert_includes result[1], "Subtitle"
  end

  def test_render_nested_formatting
    renderer = FlowChat::Intercom::Renderer.new("**bold and *italic* inside**")
    result = renderer.render

    assert_equal :text, result[0]
    assert_includes result[1], "<strong>"
    assert_includes result[1], "<em>"
  end

  # HTML sanitization tests

  def test_disallowed_tags_stripped
    renderer = FlowChat::Intercom::Renderer.new("Hello <script>alert('xss')</script> World")
    result = renderer.render

    assert_equal :text, result[0]
    refute_includes result[1], "<script>"
    refute_includes result[1], "</script>"
  end

  def test_div_tags_stripped
    renderer = FlowChat::Intercom::Renderer.new("Hello <div>content</div> World")
    result = renderer.render

    assert_equal :text, result[0]
    refute_includes result[1], "<div>"
  end

  def test_span_tags_stripped
    renderer = FlowChat::Intercom::Renderer.new("Hello <span style='color:red'>red</span> World")
    result = renderer.render

    assert_equal :text, result[0]
    refute_includes result[1], "<span>"
    refute_includes result[1], "style"
  end

  def test_disallowed_attributes_stripped
    renderer = FlowChat::Intercom::Renderer.new('<a href="https://example.com" onclick="alert()">link</a>')
    result = renderer.render

    assert_equal :text, result[0]
    assert_includes result[1], 'href="https://example.com"'
    refute_includes result[1], "onclick"
  end

  def test_valid_html_tags_preserved
    renderer = FlowChat::Intercom::Renderer.new("Hello <b>bold</b> and <i>italic</i>")
    result = renderer.render

    assert_equal :text, result[0]
    assert_includes result[1], "<b>bold</b>"
    assert_includes result[1], "<i>italic</i>"
  end

  def test_target_attribute_allowed_on_links
    renderer = FlowChat::Intercom::Renderer.new('<a href="https://example.com" target="_blank">link</a>')
    result = renderer.render

    assert_equal :text, result[0]
    assert_includes result[1], 'target="_blank"'
  end

  # Smart quotes tests

  def test_straight_quotes_preserved
    renderer = FlowChat::Intercom::Renderer.new("He said 'hello' and \"goodbye\"")
    result = renderer.render

    assert_equal :text, result[0]
    # Should have straight quotes, not curly quotes
    assert_includes result[1], "'"
    assert_includes result[1], '"'
    refute_includes result[1], "\u2018"  # left single curly quote
    refute_includes result[1], "\u201C"  # left double curly quote
  end
end

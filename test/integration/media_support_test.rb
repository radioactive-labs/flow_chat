require "test_helper"

class MediaSupportTest < Minitest::Test
  def setup
    @ussd_context = FlowChat::Context.new
    @ussd_context.session = create_test_session_store
    @ussd_context["request.msisdn"] = "+1234567890"
    @ussd_context["request.message_id"] = "test_message_123"
    @ussd_context["request.timestamp"] = Time.now
    @ussd_context.session.set("$started_at$", "2023-12-01T10:00:00Z")

    @whatsapp_context = FlowChat::Context.new
    @whatsapp_context.session = create_test_session_store
    @whatsapp_context["request.msisdn"] = "+1234567890"
    @whatsapp_context["request.message_id"] = "whatsapp_message_123"
    @whatsapp_context["request.timestamp"] = Time.now
    @whatsapp_context["request.contact_name"] = "John Doe"
    @whatsapp_context.session.set("$started_at$", "2023-12-01T10:00:00Z")
  end

  # ============================================================================
  # WHATSAPP MEDIA FLOW TESTS
  # ============================================================================

  def test_whatsapp_ask_with_media_shows_media_prompt
    @whatsapp_context.input = nil
    app = FlowChat::Whatsapp::App.new(@whatsapp_context)

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      flow = MediaTestFlow.new(app)
      flow.test_ask_with_image
    end

    assert_equal :media_image, error.prompt[0]
    assert_equal "https://example.com/help.jpg", error.prompt[2][:url]
    assert_equal "What do you think of this product?", error.prompt[2][:caption]
  end

  def test_whatsapp_ask_with_media_processes_user_input
    @whatsapp_context.input = "I love it!"
    app = FlowChat::Whatsapp::App.new(@whatsapp_context)
    flow = MediaTestFlow.new(app)
    result = flow.test_ask_with_image

    assert_equal "I love it!", result
  end

  def test_whatsapp_say_with_media_shows_media_message
    @whatsapp_context.input = nil
    app = FlowChat::Whatsapp::App.new(@whatsapp_context)

    error = assert_raises(FlowChat::Interrupt::Terminate) do
      flow = MediaTestFlow.new(app)
      flow.test_say_with_document
    end

    assert_equal :media_document, error.prompt[0]
    assert_equal "https://example.com/receipt.pdf", error.prompt[2][:url]
    assert_equal "Here's your receipt:", error.prompt[2][:caption]
    assert_equal "receipt.pdf", error.prompt[2][:filename]
  end

  def test_whatsapp_media_with_validation_error
    @whatsapp_context.input = "12"  # Invalid age
    app = FlowChat::Whatsapp::App.new(@whatsapp_context)

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      flow = MediaTestFlow.new(app)
      flow.test_ask_with_validation
    end

    # When validation fails, WhatsApp shows text error with original message
    assert_equal :text, error.prompt[0]
    assert_includes error.prompt[1], "Must be 18 or older"
    assert_includes error.prompt[1], "Enter your age:"
  end

  def test_whatsapp_sticker_without_caption
    @whatsapp_context.input = nil
    app = FlowChat::Whatsapp::App.new(@whatsapp_context)

    error = assert_raises(FlowChat::Interrupt::Terminate) do
      flow = MediaTestFlow.new(app)
      flow.test_say_sticker
    end

    assert_equal :media_sticker, error.prompt[0]
    assert_equal "https://example.com/happy.webp", error.prompt[2][:url]
    refute error.prompt[2].key?(:caption)  # Stickers don't have captions
  end

  # ============================================================================
  # USSD MEDIA FLOW TESTS
  # ============================================================================

  def test_ussd_ask_with_media_includes_url_in_text
    @ussd_context.input = nil
    app = FlowChat::Ussd::App.new(@ussd_context)

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      flow = MediaTestFlow.new(app)
      flow.test_ask_with_image
    end

    expected_message = "What do you think of this product?\n\n📷 Image: https://example.com/help.jpg"
    assert_equal expected_message, error.prompt
  end

  def test_ussd_ask_with_media_processes_user_input
    @ussd_context.input = "Great product!"
    app = FlowChat::Ussd::App.new(@ussd_context)
    flow = MediaTestFlow.new(app)
    result = flow.test_ask_with_image

    assert_equal "Great product!", result
  end

  def test_ussd_say_with_media_includes_url_in_text
    app = FlowChat::Ussd::App.new(@ussd_context)

    error = assert_raises(FlowChat::Interrupt::Terminate) do
      flow = MediaTestFlow.new(app)
      flow.test_say_with_document
    end

    expected_message = "Here's your receipt:\n\n📄 Document: https://example.com/receipt.pdf"
    assert_equal expected_message, error.prompt
  end

  def test_ussd_media_with_validation_error_includes_media_url
    @ussd_context.input = "12"  # Invalid age
    app = FlowChat::Ussd::App.new(@ussd_context)

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      flow = MediaTestFlow.new(app)
      flow.test_ask_with_validation
    end

    # Should include both validation error and original prompt with media
    assert_includes error.prompt, "Must be 18 or older"
    assert_includes error.prompt, "Enter your age:"
    assert_includes error.prompt, "📷 Image: https://example.com/age_verification.jpg"
  end

  def test_ussd_all_media_types_have_correct_icons
    app = FlowChat::Ussd::App.new(@ussd_context)

    # Test all media types
    media_types = [
      {type: :image, url: "https://example.com/img.jpg", icon: "📷", label: "Image"},
      {type: :document, url: "https://example.com/doc.pdf", icon: "📄", label: "Document"},
      {type: :video, url: "https://example.com/vid.mp4", icon: "🎥", label: "Video"},
      {type: :audio, url: "https://example.com/aud.mp3", icon: "🎵", label: "Audio"},
      {type: :sticker, url: "https://example.com/sticker.webp", icon: "😊", label: "Sticker"}
    ]

    media_types.each do |media|
      error = assert_raises(FlowChat::Interrupt::Terminate) do
        flow = MediaTestFlow.new(app)
        flow.test_say_with_media_type(media[:type], media[:url])
      end

      expected_message = "Check this out:\n\n#{media[:icon]} #{media[:label]}: #{media[:url]}"
      assert_equal expected_message, error.prompt
    end
  end

  # ============================================================================
  # CROSS-PLATFORM COMPATIBILITY TESTS
  # ============================================================================

  def test_same_flow_works_on_both_platforms
    # Test the same flow method on both platforms
    media_hash = {type: :image, url: "https://example.com/product.jpg"}

    # WhatsApp - should get media prompt
    whatsapp_app = FlowChat::Whatsapp::App.new(@whatsapp_context)
    whatsapp_error = assert_raises(FlowChat::Interrupt::Prompt) do
      flow = MediaTestFlow.new(whatsapp_app)
      flow.test_cross_platform_ask(media_hash)
    end
    assert_equal :media_image, whatsapp_error.prompt[0]

    # USSD - should get text with URL
    ussd_app = FlowChat::Ussd::App.new(@ussd_context)
    ussd_error = assert_raises(FlowChat::Interrupt::Prompt) do
      flow = MediaTestFlow.new(ussd_app)
      flow.test_cross_platform_ask(media_hash)
    end
    assert_includes ussd_error.prompt, "📷 Image: https://example.com/product.jpg"
  end

  def test_flow_without_media_works_normally_on_both_platforms
    # WhatsApp
    whatsapp_app = FlowChat::Whatsapp::App.new(@whatsapp_context)
    whatsapp_error = assert_raises(FlowChat::Interrupt::Prompt) do
      flow = MediaTestFlow.new(whatsapp_app)
      flow.test_ask_without_media
    end
    assert_equal :text, whatsapp_error.prompt[0]
    assert_equal "What's your name?", whatsapp_error.prompt[1]

    # USSD
    ussd_app = FlowChat::Ussd::App.new(@ussd_context)
    ussd_error = assert_raises(FlowChat::Interrupt::Prompt) do
      flow = MediaTestFlow.new(ussd_app)
      flow.test_ask_without_media
    end
    assert_equal "What's your name?", ussd_error.prompt
  end

  # ============================================================================
  # EDGE CASE TESTS
  # ============================================================================

  def test_media_with_complex_workflow
    # Test media support in a more complex workflow with screens
    @whatsapp_context.input = nil
    app = FlowChat::Whatsapp::App.new(@whatsapp_context)

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      flow = MediaTestFlow.new(app)
      flow.complex_media_workflow
    end

    # Should show the first screen with media
    assert_equal :media_image, error.prompt[0]
    assert_equal "https://example.com/step1.jpg", error.prompt[2][:url]
    assert_equal "Step 1: Choose your preference", error.prompt[2][:caption]
  end

  def test_media_url_vs_path_handling
    whatsapp_app = FlowChat::Whatsapp::App.new(@whatsapp_context)

    # Test with URL
    error1 = assert_raises(FlowChat::Interrupt::Prompt) do
      flow = MediaTestFlow.new(whatsapp_app)
      flow.test_media_with_url
    end
    assert_equal "https://example.com/image.jpg", error1.prompt[2][:url]

    # Test with path (should be treated as URL in the prompt system)
    error2 = assert_raises(FlowChat::Interrupt::Prompt) do
      flow = MediaTestFlow.new(whatsapp_app)
      flow.test_media_with_path
    end
    assert_equal "/local/path/image.jpg", error2.prompt[2][:url]
  end

  private

  def create_test_session_store
    Class.new do
      def initialize(context = nil)
        @data = {}
        @context = context
      end

      def get(key)
        @data[key.to_s]
      end

      def set(key, value)
        @data[key.to_s] = value
      end

      def delete(key)
        @data.delete(key.to_s)
      end

      def clear
        @data.clear
      end
    end.new
  end
end

# ============================================================================
# TEST FLOW CLASS
# ============================================================================

class MediaTestFlow < FlowChat::Flow
  def test_ask_with_image
    app.screen(:product_feedback) do |prompt|
      prompt.ask "What do you think of this product?", media: {
        type: :image,
        url: "https://example.com/help.jpg"
      }
    end
  end

  def test_say_with_document
    app.screen(:send_document) do |prompt|
      prompt.say "Here's your receipt:", media: {
        type: :document,
        url: "https://example.com/receipt.pdf",
        filename: "receipt.pdf"
      }
    end
  end

  def test_ask_with_validation
    app.screen(:age_verification) do |prompt|
      prompt.ask "Enter your age:",
        media: {type: :image, url: "https://example.com/age_verification.jpg"},
        convert: ->(input) { input.to_i },
        validate: ->(age) { "Must be 18 or older" unless age >= 18 }
    end
  end

  def test_say_sticker
    app.screen(:send_sticker) do |prompt|
      prompt.say "Thanks for your order!", media: {
        type: :sticker,
        url: "https://example.com/happy.webp"
      }
    end
  end

  def test_say_with_media_type(type, url)
    # Use a unique screen name for each test to avoid duplication
    screen_name = "send_media_#{type}_#{url.gsub(/[^a-zA-Z0-9]/, "_")}"
    app.screen(screen_name.to_sym) do |prompt|
      prompt.say "Check this out:", media: {
        type: type,
        url: url
      }
    end
  end

  def test_cross_platform_ask(media_hash)
    app.screen(:cross_platform_test) do |prompt|
      prompt.ask "Rate this product:", media: media_hash
    end
  end

  def test_ask_without_media
    app.screen(:name_input) do |prompt|
      prompt.ask "What's your name?"
    end
  end

  def complex_media_workflow
    step1 = app.screen(:step1) do |prompt|
      prompt.ask "Step 1: Choose your preference", media: {
        type: :image,
        url: "https://example.com/step1.jpg"
      }
    end

    step2 = app.screen(:step2) do |prompt|
      prompt.ask "Step 2: Confirm your choice: #{step1}", media: {
        type: :document,
        url: "https://example.com/confirmation.pdf"
      }
    end

    app.screen(:final_message) do |prompt|
      prompt.say "Workflow complete! You chose: #{step1}, confirmed: #{step2}", media: {
        type: :video,
        url: "https://example.com/thank_you.mp4"
      }
    end
  end

  def test_media_with_url
    app.screen(:url_test) do |prompt|
      prompt.ask "Test with URL:", media: {
        type: :image,
        url: "https://example.com/image.jpg"
      }
    end
  end

  def test_media_with_path
    app.screen(:path_test) do |prompt|
      prompt.ask "Test with path:", media: {
        type: :image,
        url: "/local/path/image.jpg"  # Use url instead of path for consistency
      }
    end
  end
end

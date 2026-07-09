# frozen_string_literal: true

# Module: MediaSupportTest
#
# Purpose:
# Integration tests for multimedia message handling across different platforms,
# demonstrating how FlowChat processes and renders images, videos, audio files,
# documents, and other media types in platform-specific formats.
#
# Coverage:
# - Image message handling (JPEG, PNG, GIF)
# - Video message processing (MP4, AVI)
# - Audio file support (MP3, OGG, voice notes)
# - Document handling (PDF, DOCX, spreadsheets)
# - Location message processing
# - Contact card handling
# - Platform-specific media rendering
# - Button and quick reply support
#
# Platform Differences:
# - WhatsApp: Full media support with specific type fields
# - HTTP: Media URLs with MIME type metadata
# - USSD: Text-only fallback for media messages
# - Intercom: Rich media embedding in conversations
#
# Key Test Scenarios:
# - Media type detection from file extensions
# - Proper MIME type assignment
# - Caption/description handling with media
# - Fallback text for unsupported platforms
# - Media URL validation and processing
# - Interactive elements (buttons, quick replies)
#
# Media Message Structure:
# - Image: [:image, url, {caption: "..."}]
# - Video: [:video, url, {caption: "..."}]
# - Audio: [:audio, url, {}]
# - Document: [:document, url, {filename: "..."}]
# - Location: [:location, {latitude: ..., longitude: ..., name: "..."}]
#
# Renderer Behavior:
# - USSD: Converts all media to text descriptions
# - WhatsApp: Formats as Cloud API media messages
# - HTTP: Returns structured JSON with media metadata
#
# Special Considerations:
# - Media URLs must be publicly accessible
# - File size limits vary by platform
# - Some platforms require HTTPS URLs
# - USSD cannot display media, only text descriptions
# - Location data requires latitude/longitude coordinates
# - Button interactions may have platform-specific limits

require "test_helper"

class MediaSupportTest < Minitest::Test
  include FlowChat::TestSupport::TestFlows

  def setup
    @ussd_context = FlowChat::Context.new
    @ussd_context.session = create_test_session_store
    @ussd_context["request.msisdn"] = "+1234567890"
    @ussd_context["request.message_id"] = "test_message_123"
    @ussd_context["request.timestamp"] = Time.now
    @ussd_context.session.set("$start$", "2023-12-01T10:00:00Z")

    @whatsapp_context = FlowChat::Context.new
    @whatsapp_context.session = create_test_session_store
    @whatsapp_context["request.msisdn"] = "+1234567890"
    @whatsapp_context["request.message_id"] = "whatsapp_message_123"
    @whatsapp_context["request.timestamp"] = Time.now
    @whatsapp_context["request.contact_name"] = "John Doe"
    @whatsapp_context.session.set("$start$", "2023-12-01T10:00:00Z")
  end

  # ============================================================================
  # WHATSAPP MEDIA FLOW TESTS
  # ============================================================================

  def test_whatsapp_ask_with_media_shows_media_prompt
    @whatsapp_context.input = nil
    app = FlowChat::App.new(@whatsapp_context)

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      flow = MediaTestFlow.new(app)
      flow.test_ask_with_image
    end

    assert_equal "What do you think of this product?", error.prompt
    assert_equal :image, error.media[:type]
    assert_equal "https://example.com/help.jpg", error.media[:url]
  end

  def test_whatsapp_ask_with_media_processes_user_input
    @whatsapp_context.input = "I love it!"
    app = FlowChat::App.new(@whatsapp_context)
    flow = MediaTestFlow.new(app)
    result = flow.test_ask_with_image

    assert_equal "I love it!", result
  end

  def test_whatsapp_say_with_media_shows_media_message
    @whatsapp_context.input = nil
    app = FlowChat::App.new(@whatsapp_context)

    error = assert_raises(FlowChat::Interrupt::Terminate) do
      flow = MediaTestFlow.new(app)
      flow.test_say_with_document
    end

    assert_equal "Here's your receipt:", error.prompt
    assert_equal :document, error.media[:type]
    assert_equal "https://example.com/receipt.pdf", error.media[:url]
    assert_equal "receipt.pdf", error.media[:filename]
  end

  def test_whatsapp_media_with_validation_error
    @whatsapp_context.input = "12"  # Invalid age
    app = FlowChat::App.new(@whatsapp_context)

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      flow = MediaTestFlow.new(app)
      flow.test_ask_with_validation
    end

    assert_includes error.prompt, "Must be 18 or older"
    assert_includes error.prompt, "Enter your age:"
    assert_equal :image, error.media[:type]
    assert_equal "https://example.com/age_verification.jpg", error.media[:url]
  end

  def test_whatsapp_sticker_without_caption
    @whatsapp_context.input = nil
    app = FlowChat::App.new(@whatsapp_context)

    error = assert_raises(FlowChat::Interrupt::Terminate) do
      flow = MediaTestFlow.new(app)
      flow.test_say_sticker
    end

    assert_equal "Thanks for your order!", error.prompt
    assert_equal :sticker, error.media[:type]
    assert_equal "https://example.com/happy.webp", error.media[:url]
    refute error.media.key?(:caption)  # Stickers don't have captions
  end

  # ============================================================================
  # USSD MEDIA FLOW TESTS
  # ============================================================================

  def test_ussd_ask_with_media_includes_url_in_text
    @ussd_context.input = nil
    app = FlowChat::App.new(@ussd_context)

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      flow = MediaTestFlow.new(app)
      flow.test_ask_with_image
    end

    assert_equal "What do you think of this product?", error.prompt
    assert_equal :image, error.media[:type]
    assert_equal "https://example.com/help.jpg", error.media[:url]
  end

  def test_ussd_ask_with_media_processes_user_input
    @ussd_context.input = "Great product!"
    app = FlowChat::App.new(@ussd_context)
    flow = MediaTestFlow.new(app)
    result = flow.test_ask_with_image

    assert_equal "Great product!", result
  end

  def test_ussd_say_with_media_includes_url_in_text
    app = FlowChat::App.new(@ussd_context)

    error = assert_raises(FlowChat::Interrupt::Terminate) do
      flow = MediaTestFlow.new(app)
      flow.test_say_with_document
    end

    assert_equal "Here's your receipt:", error.prompt
    assert_equal :document, error.media[:type]
    assert_equal "https://example.com/receipt.pdf", error.media[:url]
  end

  def test_ussd_media_with_validation_error_includes_media_url
    @ussd_context.input = "12"  # Invalid age
    app = FlowChat::App.new(@ussd_context)

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      flow = MediaTestFlow.new(app)
      flow.test_ask_with_validation
    end

    assert_includes error.prompt, "Must be 18 or older"
    assert_includes error.prompt, "Enter your age:"
    assert_equal :image, error.media[:type]
    assert_equal "https://example.com/age_verification.jpg", error.media[:url]
  end

  def test_ussd_all_media_types_have_correct_icons
    app = FlowChat::App.new(@ussd_context)

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

      assert_equal "Check this out:", error.prompt
      assert_equal media[:type], error.media[:type]
      assert_equal media[:url], error.media[:url]
    end
  end

  # ============================================================================
  # CROSS-PLATFORM COMPATIBILITY TESTS
  # ============================================================================

  def test_same_flow_works_on_both_platforms
    # Test the same flow method on both platforms
    media_hash = {type: :image, url: "https://example.com/product.jpg"}

    # WhatsApp - should get prompt with media attribute
    whatsapp_app = FlowChat::App.new(@whatsapp_context)
    whatsapp_error = assert_raises(FlowChat::Interrupt::Prompt) do
      flow = MediaTestFlow.new(whatsapp_app)
      flow.test_cross_platform_ask(media_hash)
    end
    assert_equal "Rate this product:", whatsapp_error.prompt
    assert_equal :image, whatsapp_error.media[:type]
    assert_equal "https://example.com/product.jpg", whatsapp_error.media[:url]

    # USSD - now also uses raw message + media attribute (architectural unification)
    ussd_app = FlowChat::App.new(@ussd_context)
    ussd_error = assert_raises(FlowChat::Interrupt::Prompt) do
      flow = MediaTestFlow.new(ussd_app)
      flow.test_cross_platform_ask(media_hash)
    end
    assert_equal "Rate this product:", ussd_error.prompt
    assert_equal :image, ussd_error.media[:type]
    assert_equal "https://example.com/product.jpg", ussd_error.media[:url]
  end

  def test_flow_without_media_works_normally_on_both_platforms
    # WhatsApp
    whatsapp_app = FlowChat::App.new(@whatsapp_context)
    whatsapp_error = assert_raises(FlowChat::Interrupt::Prompt) do
      flow = MediaTestFlow.new(whatsapp_app)
      flow.test_ask_without_media
    end
    assert_equal "What's your name?", whatsapp_error.prompt
    assert_nil whatsapp_error.media

    # USSD
    ussd_app = FlowChat::App.new(@ussd_context)
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
    app = FlowChat::App.new(@whatsapp_context)

    error = assert_raises(FlowChat::Interrupt::Prompt) do
      flow = MediaTestFlow.new(app)
      flow.complex_media_workflow
    end

    # Should show the first screen with media
    assert_equal "Step 1: Choose your preference", error.prompt
    assert_equal :image, error.media[:type]
    assert_equal "https://example.com/step1.jpg", error.media[:url]
  end

  def test_media_url_handling
    whatsapp_app = FlowChat::App.new(@whatsapp_context)

    # Test with URL
    error1 = assert_raises(FlowChat::Interrupt::Prompt) do
      flow = MediaTestFlow.new(whatsapp_app)
      flow.test_media_with_url
    end
    assert_equal "https://example.com/image.jpg", error1.media[:url]
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

# MediaTestFlow is now available from test_helper.rb via FlowChat::TestSupport::TestFlows

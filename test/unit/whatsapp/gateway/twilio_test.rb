require "test_helper"
require "webmock/minitest"

class WhatsappTwilioGatewayTest < Minitest::Test
  def setup
    # Create a mock configuration for testing
    @mock_config = FlowChat::Whatsapp::TwilioConfiguration.new("test_config")
    @mock_config.account_sid = "test_account_sid"
    @mock_config.auth_token = "test_auth_token"
    @mock_config.phone_number = "+15551234567"

    @gateway = FlowChat::Whatsapp::Gateway::Twilio.new(proc { |context| [:text, "Response", nil, nil] }, @mock_config)

    # Setup WebMock for HTTP request stubbing
    WebMock.enable!
    WebMock.reset!

    # Stub the Twilio messages API
    stub_request(:post, @mock_config.messages_url)
      .to_return(status: 201, body: {"sid" => "SM123", "status" => "queued"}.to_json)
  end

  def teardown
    WebMock.disable!
    WebMock.reset!
  end

  def test_post_request_text_message_processing
    # Disable signature validation for this test
    @mock_config.skip_signature_validation = true

    context = create_context_with_request(
      method: :post,
      params: create_text_message_params("Hello", "SM123")
    )

    gateway = FlowChat::Whatsapp::Gateway::Twilio.new(proc { |context| [:text, "Response", nil, nil] }, @mock_config)
    gateway.call(context)

    # Verify context was set correctly
    assert_equal "Hello", context.input
    assert_equal "+256700000000", context["request.msisdn"]
    assert_equal "SM123", context["request.message_id"]
    assert_equal :whatsapp_twilio, context["request.gateway"]
    assert_equal "+15551234567", context["request.to_number"]
  end

  def test_post_request_media_message_processing
    # Disable signature validation for this test
    @mock_config.skip_signature_validation = true

    context = create_context_with_request(
      method: :post,
      params: create_media_message_params("https://example.com/image.jpg", "image/jpeg", "SM456")
    )

    gateway = FlowChat::Whatsapp::Gateway::Twilio.new(proc { |context| [:text, "Response", nil, nil] }, @mock_config)
    gateway.call(context)

    expected_media = {
      "type" => "image",
      "items" => [{
        "url" => "https://example.com/image.jpg",
        "content_type" => "image/jpeg"
      }]
    }
    assert_equal expected_media, context["request.media"]
    assert_equal "+256700000000", context["request.msisdn"]
    assert_equal "SM456", context["request.message_id"]
    assert_equal "$media$", context.input
  end

  def test_non_whatsapp_message_handling
    # Disable signature validation for this test
    @mock_config.skip_signature_validation = true

    context = create_context_with_request(
      method: :post,
      params: {
        "MessageSid" => "SM123",
        "From" => "+256700000000",  # Regular SMS, not WhatsApp format
        "To" => "+15551234567",
        "Body" => "Hello"
      }
    )

    gateway = FlowChat::Whatsapp::Gateway::Twilio.new(proc { |context| [:text, "Response", nil, nil] }, @mock_config)
    gateway.call(context)

    # Should return OK but not process as WhatsApp message
    assert_equal :ok, context.controller.last_head_status
    assert_nil context.input
  end

  def test_bad_request_handling
    context = create_context_with_request(method: :get)

    @gateway.call(context)

    assert_equal :bad_request, context.controller.last_head_status
  end

  def test_missing_message_sid_handling
    # Disable signature validation for this test to focus on MessageSid validation
    @mock_config.skip_signature_validation = true

    context = create_context_with_request(
      method: :post,
      params: {
        "From" => "whatsapp:+256700000000",
        "To" => "whatsapp:+15551234567",
        "Body" => "Hello"
        # Missing MessageSid
      }
    )

    gateway = FlowChat::Whatsapp::Gateway::Twilio.new(proc { |context| [:text, "Response", nil, nil] }, @mock_config)
    gateway.call(context)

    assert_equal :bad_request, context.controller.last_head_status
    assert_nil context.input
  end

  # ============================================================================
  # WEBHOOK SIGNATURE VALIDATION TESTS
  # ============================================================================

  def test_valid_webhook_signature
    # Set up auth_token for signature validation
    @mock_config.auth_token = "test_auth_token"

    params = create_text_message_params("Hello", "SM123")
    url = "https://example.com/webhook"

    # Calculate valid Twilio signature
    signature_string = url + params.sort.map { |k, v| "#{k}#{v}" }.join
    signature = Base64.strict_encode64(
      OpenSSL::HMAC.digest(
        OpenSSL::Digest.new("sha1"),
        "test_auth_token",
        signature_string
      )
    )

    context = create_context_with_request(
      method: :post,
      params: params,
      url: url,
      headers: {
        "X-Twilio-Signature" => signature
      }
    )

    gateway = FlowChat::Whatsapp::Gateway::Twilio.new(proc { |context| [:text, "Response", nil, nil] }, @mock_config)
    gateway.call(context)

    # Should process successfully with valid signature
    assert_equal "Hello", context.input
    assert_equal "+256700000000", context["request.msisdn"]
  end

  def test_invalid_webhook_signature
    # Set up auth_token for signature validation
    @mock_config.auth_token = "test_auth_token"

    params = create_text_message_params("Hello", "SM123")

    context = create_context_with_request(
      method: :post,
      params: params,
      url: "https://example.com/webhook",
      headers: {
        "X-Twilio-Signature" => "invalid_signature_here"
      }
    )

    gateway = FlowChat::Whatsapp::Gateway::Twilio.new(proc { |context| [:text, "Response", nil, nil] }, @mock_config)
    gateway.call(context)

    # Should reject with unauthorized status
    assert_equal :unauthorized, context.controller.last_head_status
    assert_nil context.input
  end

  def test_missing_webhook_signature_header
    # Set up auth_token for signature validation
    @mock_config.auth_token = "test_auth_token"

    params = create_text_message_params("Hello", "SM123")

    context = create_context_with_request(
      method: :post,
      params: params,
      url: "https://example.com/webhook"
      # No signature header provided
    )

    gateway = FlowChat::Whatsapp::Gateway::Twilio.new(proc { |context| [:text, "Response", nil, nil] }, @mock_config)
    gateway.call(context)

    # Should reject with unauthorized status
    assert_equal :unauthorized, context.controller.last_head_status
    assert_nil context.input
  end

  def test_webhook_validation_explicitly_disabled
    # Explicitly disable signature validation
    @mock_config.auth_token = nil
    @mock_config.skip_signature_validation = true

    params = create_text_message_params("Hello", "SM123")

    context = create_context_with_request(
      method: :post,
      params: params,
      url: "https://example.com/webhook"
      # No signature header - should be fine when explicitly disabled
    )

    gateway = FlowChat::Whatsapp::Gateway::Twilio.new(proc { |context| [:text, "Response", nil, nil] }, @mock_config)
    gateway.call(context)

    # Should process successfully when validation is explicitly disabled
    assert_equal "Hello", context.input
    assert_equal "+256700000000", context["request.msisdn"]
  end

  def test_configuration_error_message_provides_helpful_guidance
    @mock_config.auth_token = nil

    params = create_text_message_params("Hello", "SM123")

    context = create_context_with_request(
      method: :post,
      params: params,
      url: "https://example.com/webhook"
    )

    gateway = FlowChat::Whatsapp::Gateway::Twilio.new(proc { |context| [:text, "Response", nil, nil] }, @mock_config)

    # Should raise ConfigurationError with helpful message
    error = assert_raises(FlowChat::Whatsapp::ConfigurationError) do
      gateway.call(context)
    end

    assert_includes error.message, "auth_token is required"
    assert_includes error.message, "skip_signature_validation=true"
  end

  def test_secure_compare_method
    gateway = FlowChat::Whatsapp::Gateway::Twilio.new(proc { |context| [:text, "Response", nil, nil] }, @mock_config)

    # Test identical strings
    assert gateway.send(:secure_compare, "hello", "hello")

    # Test different strings of same length
    refute gateway.send(:secure_compare, "hello", "world")

    # Test different lengths
    refute gateway.send(:secure_compare, "hello", "hi")
    refute gateway.send(:secure_compare, "hi", "hello")

    # Test empty strings
    assert gateway.send(:secure_compare, "", "")
    refute gateway.send(:secure_compare, "", "hello")
  end

  private

  def create_context_with_request(method:, params: {}, url: "https://example.com/webhook", headers: {}, cookies: {})
    context = FlowChat::Context.new

    # Create mock request
    request = OpenStruct.new(params: params, headers: headers, cookies: cookies, url: url)
    request.define_singleton_method(:get?) { method == :get }
    request.define_singleton_method(:post?) { method == :post }
    request.define_singleton_method(:POST) { params }

    # Create mock controller
    controller = OpenStruct.new(request: request)

    # Add mock response for streaming
    mock_response = FlowChat::TestSupport::MockResponse.new
    controller.define_singleton_method(:response) { mock_response }

    # Track render calls
    controller.define_singleton_method(:render) do |options|
      @last_render = options
    end
    controller.define_singleton_method(:last_render) { @last_render }

    # Track head calls
    controller.define_singleton_method(:head) do |status, options = {}|
      @last_head_status = status
      @last_head_options = options
    end
    controller.define_singleton_method(:last_head_status) { @last_head_status }

    context["controller"] = controller
    context
  end

  def create_text_message_params(text, message_sid)
    {
      "MessageSid" => message_sid,
      "From" => "whatsapp:+256700000000",
      "To" => "whatsapp:+15551234567",
      "Body" => text,
      "NumMedia" => "0"
    }
  end

  def create_media_message_params(media_url, content_type, message_sid)
    {
      "MessageSid" => message_sid,
      "From" => "whatsapp:+256700000000",
      "To" => "whatsapp:+15551234567",
      "Body" => "",
      "NumMedia" => "1",
      "MediaUrl0" => media_url,
      "MediaContentType0" => content_type
    }
  end
end

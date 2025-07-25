require "test_helper"
require "webmock/minitest"

class WhatsappCloudApiGatewayTest < Minitest::Test
  def setup
    # Create a mock configuration for testing
    @mock_config = FlowChat::Whatsapp::Configuration.new("test_config")
    @mock_config.verify_token = "test_verify_token"
    @mock_config.phone_number_id = "test_phone_id"
    @mock_config.access_token = "test_access_token"
    @mock_config.app_secret = "test_app_secret"

    @gateway = FlowChat::Whatsapp::Gateway::CloudApi.new(proc { |context| [:text, "Response", nil, nil] }, @mock_config)

    # Setup WebMock for HTTP request stubbing
    WebMock.enable!
    WebMock.reset!

    # Stub the WhatsApp messages API
    stub_request(:post, @mock_config.messages_url)
      .to_return(status: 200, body: {"messages" => [{"id" => "sent_123"}]}.to_json)
  end

  def teardown
    WebMock.disable!
    WebMock.reset!
  end

  def test_get_request_webhook_verification
    context = create_context_with_request(
      method: :get,
      params: {
        "hub.mode" => "subscribe",
        "hub.verify_token" => "test_verify_token",
        "hub.challenge" => "test_challenge"
      }
    )

    @gateway.call(context)

    # Should render the challenge as plain text
    assert_equal "test_challenge", context.controller.last_render[:plain]
  end

  def test_get_request_invalid_verify_token
    context = create_context_with_request(
      method: :get,
      params: {
        "hub.mode" => "subscribe",
        "hub.verify_token" => "invalid_token",
        "hub.challenge" => "test_challenge"
      }
    )

    @gateway.call(context)

    # Should return forbidden
    assert_equal :forbidden, context.controller.last_head_status
  end

  def test_post_request_text_message_processing
    context = create_context_with_request(
      method: :post,
      body: create_text_message_payload("Hello", "wamid.test123")
    )

    @gateway.call(context)

    # Verify context was set correctly
    assert_equal "Hello", context.input
    assert_equal "+256700000000", context["request.msisdn"]
    assert_equal "wamid.test123", context["request.message_id"]
    assert_equal "John Doe", context["request.contact_name"]
    assert_equal :whatsapp_cloud_api, context["request.gateway"]
    assert_equal "1702891800", context["request.timestamp"]
  end

  def test_post_request_button_response_processing
    context = create_context_with_request(
      method: :post,
      body: create_button_response_payload("btn_0", "Yes", "wamid.test456")
    )

    @gateway.call(context)

    assert_equal "btn_0", context.input
    assert_equal "+256700000000", context["request.msisdn"]
    assert_equal "wamid.test456", context["request.message_id"]
  end

  def test_post_request_list_response_processing
    context = create_context_with_request(
      method: :post,
      body: create_list_response_payload("list_1", "Option 2", "wamid.test789")
    )

    @gateway.call(context)

    assert_equal "list_1", context.input
    assert_equal "+256700000000", context["request.msisdn"]
    assert_equal "wamid.test789", context["request.message_id"]
  end

  def test_post_request_location_message_processing
    context = create_context_with_request(
      method: :post,
      body: create_location_message_payload(0.3476, 32.5825, "wamid.location123")
    )

    @gateway.call(context)

    expected_location = {
      "latitude" => 0.3476,
      "longitude" => 32.5825,
      "name" => nil,
      "address" => nil
    }
    assert_equal expected_location, context["request.location"]
    assert_equal "+256700000000", context["request.msisdn"]
    assert_equal "wamid.location123", context["request.message_id"]
    assert_equal "$location$", context.input
  end

  def test_post_request_media_message_processing
    context = create_context_with_request(
      method: :post,
      body: create_media_message_payload("media123", "image/jpeg", "wamid.media123")
    )

    @gateway.call(context)

    expected_media = {
      "type" => "image",
      "id" => "media123",
      "mime_type" => "image/jpeg",
      "caption" => nil
    }
    assert_equal expected_media, context["request.media"]
    assert_equal "+256700000000", context["request.msisdn"]
    assert_equal "wamid.media123", context["request.message_id"]
    assert_equal "$media$", context.input
  end

  def test_empty_webhook_payload_handling
    context = create_context_with_request(
      method: :post,
      body: "{}"
    )

    @gateway.call(context)

    # Should handle gracefully and return ok
    assert_equal :ok, context.controller.last_head_status
  end

  def test_malformed_webhook_payload_handling
    context = create_context_with_request(
      method: :post,
      body: "invalid json"
    )

    # Should not crash - JSON.parse error should be handled gracefully
    @gateway.call(context)

    # Should return :bad_request status with malformed JSON
    assert_equal :bad_request, context.controller.last_head_status
  end

  def test_unsupported_message_type_handling
    context = create_context_with_request(
      method: :post,
      body: create_unsupported_message_payload("wamid.unsupported123")
    )

    @gateway.call(context)

    # Should still set basic context but input might be nil
    assert_equal "+256700000000", context["request.msisdn"]
    assert_equal "wamid.unsupported123", context["request.message_id"]
    assert_nil context.input
  end

  def test_bad_request_handling
    context = create_context_with_request(method: :put)

    @gateway.call(context)

    assert_equal :bad_request, context.controller.last_head_status
  end

  # ============================================================================
  # WEBHOOK SIGNATURE VALIDATION TESTS
  # ============================================================================

  def test_valid_webhook_signature
    # Set up app_secret for signature validation
    @mock_config.app_secret = "test_app_secret"

    payload_hash = create_text_message_payload("Hello", "wamid.test123")
    payload_json = payload_hash.to_json

    # Calculate valid HMAC-SHA256 signature
    signature = OpenSSL::HMAC.hexdigest(
      OpenSSL::Digest.new("sha256"),
      "test_app_secret",
      payload_json
    )

    context = create_context_with_request(
      method: :post,
      body: payload_json,
      headers: {
        "X-Hub-Signature-256" => "sha256=#{signature}"
      }
    )

    gateway = FlowChat::Whatsapp::Gateway::CloudApi.new(proc { |context| [:text, "Response", nil, nil] }, @mock_config)
    gateway.call(context)

    # Should process successfully with valid signature
    assert_equal "Hello", context.input
    assert_equal "+256700000000", context["request.msisdn"]
    assert_equal :ok, context.controller.last_head_status
  end

  def test_invalid_webhook_signature
    # Set up app_secret for signature validation
    @mock_config.app_secret = "test_app_secret"

    payload_hash = create_text_message_payload("Hello", "wamid.test123")
    payload_json = payload_hash.to_json

    context = create_context_with_request(
      method: :post,
      body: payload_json,
      headers: {
        "X-Hub-Signature-256" => "sha256=invalid_signature_here"
      }
    )

    gateway = FlowChat::Whatsapp::Gateway::CloudApi.new(proc { |context| [:text, "Response", nil, nil] }, @mock_config)
    gateway.call(context)

    # Should reject with unauthorized status
    assert_equal :unauthorized, context.controller.last_head_status
    assert_nil context.input
  end

  def test_missing_webhook_signature_header
    # Set up app_secret for signature validation
    @mock_config.app_secret = "test_app_secret"

    payload_hash = create_text_message_payload("Hello", "wamid.test123")

    context = create_context_with_request(
      method: :post,
      body: payload_hash.to_json,
      headers: {skip_auto_signature: true}  # Skip auto-signature generation
      # No signature header provided
    )

    gateway = FlowChat::Whatsapp::Gateway::CloudApi.new(proc { |context| [:text, "Response", nil, nil] }, @mock_config)
    gateway.call(context)

    # Should reject with unauthorized status
    assert_equal :unauthorized, context.controller.last_head_status
    assert_nil context.input
  end

  def test_malformed_webhook_signature_header
    # Set up app_secret for signature validation
    @mock_config.app_secret = "test_app_secret"

    payload_hash = create_text_message_payload("Hello", "wamid.test123")

    context = create_context_with_request(
      method: :post,
      body: payload_hash.to_json,
      headers: {
        "X-Hub-Signature-256" => "malformed_header_without_sha256_prefix"
      }
    )

    gateway = FlowChat::Whatsapp::Gateway::CloudApi.new(proc { |context| [:text, "Response", nil, nil] }, @mock_config)
    gateway.call(context)

    # Should reject with unauthorized status
    assert_equal :unauthorized, context.controller.last_head_status
    assert_nil context.input
  end

  def test_webhook_validation_skipped_without_app_secret
    # Don't set app_secret (or set to nil/empty)
    @mock_config.app_secret = nil

    payload_hash = create_text_message_payload("Hello", "wamid.test123")

    context = create_context_with_request(
      method: :post,
      body: payload_hash.to_json
      # No signature header - should raise exception without app_secret
    )

    gateway = FlowChat::Whatsapp::Gateway::CloudApi.new(proc { |context| [:text, "Response", nil, nil] }, @mock_config)

    # Should raise ConfigurationError when app_secret is missing and validation not explicitly disabled
    assert_raises(FlowChat::Whatsapp::ConfigurationError) do
      gateway.call(context)
    end
  end

  def test_webhook_validation_skipped_with_empty_app_secret
    # Set app_secret to empty string
    @mock_config.app_secret = ""

    payload_hash = create_text_message_payload("Hello", "wamid.test123")

    context = create_context_with_request(
      method: :post,
      body: payload_hash.to_json
      # No signature header - should raise exception with empty app_secret
    )

    gateway = FlowChat::Whatsapp::Gateway::CloudApi.new(proc { |context| [:text, "Response", nil, nil] }, @mock_config)

    # Should raise ConfigurationError when app_secret is empty and validation not explicitly disabled
    assert_raises(FlowChat::Whatsapp::ConfigurationError) do
      gateway.call(context)
    end
  end

  def test_webhook_validation_explicitly_disabled
    # Explicitly disable signature validation
    @mock_config.app_secret = nil
    @mock_config.skip_signature_validation = true

    payload_hash = create_text_message_payload("Hello", "wamid.test123")

    context = create_context_with_request(
      method: :post,
      body: payload_hash.to_json
      # No signature header - should be fine when explicitly disabled
    )

    gateway = FlowChat::Whatsapp::Gateway::CloudApi.new(proc { |context| [:text, "Response", nil, nil] }, @mock_config)
    gateway.call(context)

    # Should process successfully when validation is explicitly disabled
    assert_equal "Hello", context.input
    assert_equal "+256700000000", context["request.msisdn"]
    assert_equal :ok, context.controller.last_head_status
  end

  def test_webhook_validation_disabled_with_app_secret_still_works
    # Test that when validation is disabled, we don't even check the signature
    @mock_config.app_secret = "test_secret"
    @mock_config.skip_signature_validation = true

    payload_hash = create_text_message_payload("Hello", "wamid.test123")

    context = create_context_with_request(
      method: :post,
      body: payload_hash.to_json,
      headers: {
        "X-Hub-Signature-256" => "sha256=completely_invalid_signature"
      }
    )

    gateway = FlowChat::Whatsapp::Gateway::CloudApi.new(proc { |context| [:text, "Response", nil, nil] }, @mock_config)
    gateway.call(context)

    # Should process successfully even with invalid signature when validation is disabled
    assert_equal "Hello", context.input
    assert_equal "+256700000000", context["request.msisdn"]
    assert_equal :ok, context.controller.last_head_status
  end

  def test_configuration_error_message_provides_helpful_guidance
    @mock_config.app_secret = nil

    payload_hash = create_text_message_payload("Hello", "wamid.test123")

    context = create_context_with_request(
      method: :post,
      body: payload_hash.to_json
    )

    gateway = FlowChat::Whatsapp::Gateway::CloudApi.new(proc { |context| [:text, "Response", nil, nil] }, @mock_config)

    # Should raise ConfigurationError with helpful message
    error = assert_raises(FlowChat::Whatsapp::ConfigurationError) do
      gateway.call(context)
    end

    assert_includes error.message, "app_secret is required"
    assert_includes error.message, "skip_signature_validation=true"
  end

  def test_signature_validation_with_different_body_content
    # Test that signature validation properly compares against actual body content
    @mock_config.app_secret = "test_app_secret"

    original_payload = create_text_message_payload("Hello", "wamid.test123")
    original_json = original_payload.to_json

    # Calculate signature for original payload
    valid_signature = OpenSSL::HMAC.hexdigest(
      OpenSSL::Digest.new("sha256"),
      "test_app_secret",
      original_json
    )

    # But send a different payload with the same signature
    different_payload = create_text_message_payload("Different message", "wamid.test456")

    context = create_context_with_request(
      method: :post,
      body: different_payload.to_json,
      headers: {
        "X-Hub-Signature-256" => "sha256=#{valid_signature}"
      }
    )

    gateway = FlowChat::Whatsapp::Gateway::CloudApi.new(proc { |context| [:text, "Response", nil, nil] }, @mock_config)
    gateway.call(context)

    # Should reject because signature doesn't match the actual body
    assert_equal :unauthorized, context.controller.last_head_status
    assert_nil context.input
  end

  def test_secure_compare_method
    gateway = FlowChat::Whatsapp::Gateway::CloudApi.new(proc { |context| [:text, "Response", nil, nil] }, @mock_config)

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

    # Test with actual HMAC signatures
    secret = "test_secret"
    message = "test_message"
    signature1 = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), secret, message)
    signature2 = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), secret, message)
    signature3 = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), secret, "different_message")

    assert gateway.send(:secure_compare, signature1, signature2)
    refute gateway.send(:secure_compare, signature1, signature3)
  end

  private

  def create_context_with_request(method:, params: {}, body: nil, headers: {}, cookies: {})
    context = FlowChat::Context.new

    # Calculate webhook signature if body is provided and app_secret is configured
    # Skip auto-generation if explicitly disabled with special marker
    if body && @mock_config.app_secret && !headers.key?("X-Hub-Signature-256") && !headers.key?(:skip_auto_signature)
      body_string = body.is_a?(String) ? body : body.to_json
      signature = OpenSSL::HMAC.hexdigest(
        OpenSSL::Digest.new("sha256"),
        @mock_config.app_secret,
        body_string
      )
      headers["X-Hub-Signature-256"] = "sha256=#{signature}"
    end

    # Remove the special marker before creating the request
    headers.delete(:skip_auto_signature)

    # Create mock request
    request = OpenStruct.new(params: params, headers: headers, cookies: cookies)
    request.define_singleton_method(:get?) { method == :get }
    request.define_singleton_method(:post?) { method == :post }

    if body
      request.define_singleton_method(:body) do
        StringIO.new(body.is_a?(String) ? body : body.to_json)
      end
    end

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

  def create_text_message_payload(text, message_id)
    {
      "entry" => [{
        "changes" => [{
          "value" => {
            "messages" => [{
              "id" => message_id,
              "from" => "256700000000",
              "timestamp" => "1702891800",
              "text" => {"body" => text},
              "type" => "text"
            }],
            "contacts" => [{
              "profile" => {"name" => "John Doe"},
              "wa_id" => "256700000000"
            }]
          }
        }]
      }]
    }
  end

  def create_button_response_payload(button_id, button_title, message_id)
    {
      "entry" => [{
        "changes" => [{
          "value" => {
            "messages" => [{
              "id" => message_id,
              "from" => "256700000000",
              "timestamp" => "1702891800",
              "interactive" => {
                "type" => "button_reply",
                "button_reply" => {"id" => button_id, "title" => button_title}
              },
              "type" => "interactive"
            }],
            "contacts" => [{
              "profile" => {"name" => "John Doe"},
              "wa_id" => "256700000000"
            }]
          }
        }]
      }]
    }
  end

  def create_list_response_payload(list_id, list_title, message_id)
    {
      "entry" => [{
        "changes" => [{
          "value" => {
            "messages" => [{
              "id" => message_id,
              "from" => "256700000000",
              "timestamp" => "1702891800",
              "interactive" => {
                "type" => "list_reply",
                "list_reply" => {"id" => list_id, "title" => list_title}
              },
              "type" => "interactive"
            }],
            "contacts" => [{
              "profile" => {"name" => "John Doe"},
              "wa_id" => "256700000000"
            }]
          }
        }]
      }]
    }
  end

  def create_location_message_payload(latitude, longitude, message_id)
    {
      "entry" => [{
        "changes" => [{
          "value" => {
            "messages" => [{
              "id" => message_id,
              "from" => "256700000000",
              "timestamp" => "1702891800",
              "location" => {
                "latitude" => latitude,
                "longitude" => longitude
              },
              "type" => "location"
            }],
            "contacts" => [{
              "profile" => {"name" => "John Doe"},
              "wa_id" => "256700000000"
            }]
          }
        }]
      }]
    }
  end

  def create_media_message_payload(media_id, mime_type, message_id)
    {
      "entry" => [{
        "changes" => [{
          "value" => {
            "messages" => [{
              "id" => message_id,
              "from" => "256700000000",
              "timestamp" => "1702891800",
              "image" => {
                "id" => media_id,
                "mime_type" => mime_type
              },
              "type" => "image"
            }],
            "contacts" => [{
              "profile" => {"name" => "John Doe"},
              "wa_id" => "256700000000"
            }]
          }
        }]
      }]
    }
  end

  def create_unsupported_message_payload(message_id)
    {
      "entry" => [{
        "changes" => [{
          "value" => {
            "messages" => [{
              "id" => message_id,
              "from" => "256700000000",
              "timestamp" => "1702891800",
              "type" => "unsupported"
            }],
            "contacts" => [{
              "profile" => {"name" => "John Doe"},
              "wa_id" => "256700000000"
            }]
          }
        }]
      }]
    }
  end
end

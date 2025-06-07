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

  # Tests for different message handling modes
  def test_inline_mode_message_handling
    # Mock inline mode
    FlowChat::Config.whatsapp.stub(:message_handling_mode, :inline) do
      # Track app execution
      app_called = false
      test_app = proc do |context|
        app_called = true
        [:text, "Response", nil, nil]
      end

      # Mock the client send_message call
      mock_client = Minitest::Mock.new
      mock_client.expect(:send_message, {"messages" => [{"id" => "sent_123"}]}, ["+256700000000", [:text, "Response", {}]])

      # Stub the WhatsApp Client class to return our mock
      FlowChat::Whatsapp::Client.stub(:new, mock_client) do
        # Create gateway which will use our mocked client
        gateway = FlowChat::Whatsapp::Gateway::CloudApi.new(test_app, @mock_config)
        context = create_context_with_request(
          method: :post,
          body: create_text_message_payload("Hello", "wamid.test123")
        )

        gateway.call(context)

        # Verify app was called and processed correctly
        assert app_called, "App should have been called"

        # In inline mode, message should be sent immediately
        mock_client.verify
        assert_equal({"messages" => [{"id" => "sent_123"}]}, context["whatsapp.message_result"])
      end
    end
  end

  def test_background_mode_message_handling
    # Mock background mode
    FlowChat::Config.whatsapp.stub(:message_handling_mode, :background) do
      FlowChat::Config.whatsapp.stub(:background_job_class, "TestBackgroundJob") do
        # Mock job class
        job_class = Minitest::Mock.new
        job_class.expect(:perform_later, true, [Hash])

        # Stub constantize to return our mock
        stub_constantize("TestBackgroundJob", job_class) do
          context = create_context_with_request(
            method: :post,
            body: create_text_message_payload("Hello", "wamid.test123")
          )

          @gateway.call(context)

          job_class.verify
        end
      end
    end
  end

  def test_background_mode_fallback_to_inline_when_job_missing
    # Mock background mode with missing job class
    FlowChat::Config.whatsapp.stub(:message_handling_mode, :background) do
      FlowChat::Config.whatsapp.stub(:background_job_class, "NonExistentJob") do
        # Create a simple mock client that tracks if send_message was called
        send_message_called = false
        mock_client = Object.new
        mock_client.define_singleton_method(:send_message) do |phone, response|
          send_message_called = true
          {"messages" => [{"id" => "fallback_123"}]}
        end

        # Capture logged warning
        logged_warning = nil
        logger_mock = Minitest::Mock.new
        logger_mock.expect(:warn, nil) { |msg|
          logged_warning = msg
          true
        }

        # Use the helper to make constantize fail for NonExistentJob
        stub_constantize_to_fail("NonExistentJob") do
          # Mock the WhatsApp Client class to return our mock
          FlowChat::Whatsapp::Client.stub(:new, mock_client) do
            Rails.stub(:logger, logger_mock) do
              gateway = FlowChat::Whatsapp::Gateway::CloudApi.new(proc { |context| [:text, "Response", nil, nil] }, @mock_config)
              context = create_context_with_request(
                method: :post,
                body: create_text_message_payload("Hello", "wamid.test123")
              )

              gateway.call(context)

              # Verify fallback behavior
              assert send_message_called, "Should have called send_message for fallback inline sending"
              assert_includes logged_warning, "Background mode requested but no NonExistentJob found. Falling back to inline sending."
              assert_equal({"messages" => [{"id" => "fallback_123"}]}, context["whatsapp.message_result"])
            end
          end
        end

        logger_mock.verify
      end
    end
  end

  def test_simulator_mode_message_handling
    # Mock simulator mode
    FlowChat::Config.whatsapp.stub(:message_handling_mode, :simulator) do
      # Mock client build_message_payload method - expects final rendered format
      mock_client = Minitest::Mock.new
      mock_client.expect(:build_message_payload, {"to" => "+256700000000", "type" => "text", "text" => {"body" => "Response"}}, [[:text, "Response", {}], "+256700000000"])

      FlowChat::Whatsapp::Client.stub(:new, mock_client) do
        # App returns new format: [type, message, choices, media]
        gateway = FlowChat::Whatsapp::Gateway::CloudApi.new(proc { |context| [:text, "Response", nil, nil] }, @mock_config)
        context = create_context_with_request(
          method: :post,
          body: create_text_message_payload("Hello", "wamid.test123")
        )

        gateway.call(context)

        mock_client.verify
        # Should render simulator response
        assert_equal "simulator", context.controller.last_render[:json][:mode]
        assert_equal true, context.controller.last_render[:json][:webhook_processed]
        assert_includes context.controller.last_render[:json], :would_send
        assert_includes context.controller.last_render[:json], :message_info
      end
    end
  end

  def test_simulator_mode_via_request_parameter
    # Set up global simulator secret
    FlowChat::Config.simulator_secret = "test_simulator_secret_123"

    # Generate valid simulator cookie
    timestamp = Time.now.to_i
    message = "simulator:#{timestamp}"
    signature = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), "test_simulator_secret_123", message)
    valid_cookie = "#{timestamp}:#{signature}"

    # Even if global mode is inline, simulator parameter should override
    FlowChat::Config.whatsapp.stub(:message_handling_mode, :inline) do
      mock_client = Minitest::Mock.new
      mock_client.expect(:build_message_payload, {"to" => "+256700000000", "type" => "text", "text" => {"body" => "Response"}}, [[:text, "Response", {}], "+256700000000"])

      FlowChat::Whatsapp::Client.stub(:new, mock_client) do
        # App returns new format: [type, message, choices, media]
        gateway = FlowChat::Whatsapp::Gateway::CloudApi.new(proc { |context| [:text, "Response", nil, nil] }, @mock_config)
        context = create_context_with_request(
          method: :post,
          body: create_text_message_payload("Hello", "wamid.test123").merge("simulator_mode" => true),
          cookies: {
            "flowchat_simulator" => valid_cookie
          }
        )

        # Enable simulator mode for this test
        context["enable_simulator"] = true

        gateway.call(context)

        mock_client.verify
        # Should render simulator response despite global inline mode
        assert_equal "simulator", context.controller.last_render[:json][:mode]
      end
    end
  ensure
    # Clean up
    FlowChat::Config.simulator_secret = nil
  end

  def test_flow_processing_happens_synchronously_in_background_mode
    # Verify that flow processing happens sync, even in background mode
    FlowChat::Config.whatsapp.stub(:message_handling_mode, :background) do
      FlowChat::Config.whatsapp.stub(:background_job_class, "TestBackgroundJob") do
        # Track if flow was called
        flow_called = false
        test_app = proc do |context|
          flow_called = true
          # Verify we have full context during flow execution
          assert_equal "Hello", context.input
          assert_equal "+256700000000", context["request.msisdn"]
          [:text, "Flow executed with context", nil, nil]
        end

        job_class = Minitest::Mock.new
        job_class.expect(:perform_later, true, [Hash])

        stub_constantize("TestBackgroundJob", job_class) do
          gateway = FlowChat::Whatsapp::Gateway::CloudApi.new(test_app, @mock_config)
          context = create_context_with_request(
            method: :post,
            body: create_text_message_payload("Hello", "wamid.test123")
          )

          gateway.call(context)

          # Flow should have been executed synchronously
          assert flow_called, "Flow should be executed synchronously even in background mode"
          job_class.verify
        end
      end
    end
  end

  def test_background_mode_preserves_controller_context
    # Verify that controller context is preserved during flow execution
    FlowChat::Config.whatsapp.stub(:message_handling_mode, :background) do
      FlowChat::Config.whatsapp.stub(:background_job_class, "TestBackgroundJob") do
        controller_preserved = false
        test_app = proc do |context|
          # Verify controller is available during flow execution
          controller_preserved = !context.controller.nil?
          [:text, "Controller context preserved", nil, nil]
        end

        job_class = Minitest::Mock.new
        job_class.expect(:perform_later, true, [Hash])

        stub_constantize("TestBackgroundJob", job_class) do
          gateway = FlowChat::Whatsapp::Gateway::CloudApi.new(test_app, @mock_config)
          context = create_context_with_request(
            method: :post,
            body: create_text_message_payload("Hello", "wamid.test123")
          )

          gateway.call(context)

          assert controller_preserved, "Controller context should be preserved during flow execution"
          job_class.verify
        end
      end
    end
  end

  def test_post_request_skips_validation_with_simulator_mode_parameter
    # Set up app_secret for signature validation and global simulator secret
    @mock_config.app_secret = "test_app_secret"
    FlowChat::Config.simulator_secret = "test_simulator_secret_123"

    # Generate valid simulator cookie
    timestamp = Time.now.to_i
    message = "simulator:#{timestamp}"
    signature = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), "test_simulator_secret_123", message)
    valid_cookie = "#{timestamp}:#{signature}"

    # Even if global mode is inline, simulator parameter should override and skip validation
    FlowChat::Config.whatsapp.stub(:message_handling_mode, :inline) do
      mock_client = Minitest::Mock.new
      mock_client.expect(:build_message_payload, {"to" => "+256700000000", "type" => "text", "text" => {"body" => "Response"}}, [[:text, "Response", {}], "+256700000000"])

      FlowChat::Whatsapp::Client.stub(:new, mock_client) do
        # App returns new format: [type, message, choices, media]
        gateway = FlowChat::Whatsapp::Gateway::CloudApi.new(proc { |context| [:text, "Response", nil, nil] }, @mock_config)

        payload_hash = create_text_message_payload("Hello", "wamid.test123")
        payload_json = payload_hash.to_json

        # Add simulator_mode to body - no webhook signature provided, should be skipped
        payload_with_simulator = JSON.parse(payload_json)
        payload_with_simulator["simulator_mode"] = true

        context = create_context_with_request(
          method: :post,
          body: payload_with_simulator.to_json,
          cookies: {
            "flowchat_simulator" => valid_cookie
          }
        )

        # Enable simulator mode for this test
        context["enable_simulator"] = true

        gateway.call(context)

        mock_client.verify
        # Should render simulator response despite no webhook signature
        assert_equal "simulator", context.controller.last_render[:json][:mode]
      end
    end
  ensure
    # Clean up
    FlowChat::Config.simulator_secret = nil
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

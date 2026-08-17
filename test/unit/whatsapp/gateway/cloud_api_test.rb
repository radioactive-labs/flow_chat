require "test_helper"
require_relative "../../../support/test_helpers"
require "webmock/minitest"

class WhatsappCloudApiGatewayTest < Minitest::Test
  include FlowChat::TestSupport::TestHelpers

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
    @subscribers&.each { |s| ActiveSupport::Notifications.unsubscribe(s) }
  end

  # WhatsApp's configuration has no test file of its own, so its predicate is
  # pinned here alongside the gateway that consumes it.
  def test_configuration_valid_returns_a_boolean_not_nil
    assert_equal true, @mock_config.valid?
    assert_equal false, FlowChat::Whatsapp::Configuration.new(nil).valid?
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
    assert_equal "John Doe", context["request.user_name"]
    assert_equal :whatsapp_cloud_api, context["request.gateway"]
    refute_equal "1702891800", context["request.timestamp"] # Now uses Time.current instead of webhook timestamp
  end

  # The other half of the same defect: the client wrapped its send in its own
  # MESSAGE_SENT instrument block while the gateway instrumented the same send,
  # so every successful delivery published the event twice and MetricsCollector
  # counted #{platform}.messages.sent at double the real rate.
  def test_message_sent_is_instrumented_exactly_once_on_a_successful_send
    sent, failed = capture_delivery_events do
      context = create_context_with_request(
        method: :post,
        body: create_text_message_payload("Hello", "wamid.test123")
      )
      @gateway.call(context)
    end

    assert_equal 1, sent.length, "one delivery must publish message.sent exactly once"
    assert_equal 0, failed.length
    assert_equal "sent_123", sent.first.payload[:platform_message_id]

    # The event is published after the send rather than wrapped around it, so
    # its own duration reads zero; the measured figure rides on the payload.
    assert_instance_of Float, sent.first.payload[:duration_ms]
    assert_operator sent.first.payload[:duration_ms], :>=, 0
  end

  # Regression: report_delivery_failure returns nil when send_message already
  # swallowed an API error (logged, not raised), and handle_message_inline
  # instrumented MESSAGE_SENT regardless - so a delivery that never happened
  # was counted as one that did, alongside the MESSAGE_DELIVERY_FAILED event
  # correctly fired for the same send.
  def test_message_sent_is_not_instrumented_when_delivery_failed
    WebMock.reset!
    stub_request(:post, @mock_config.messages_url)
      .to_return(status: 400, body: {"error" => {"message" => "rejected"}}.to_json)

    sent, failed = capture_delivery_events do
      context = create_context_with_request(
        method: :post,
        body: create_text_message_payload("Hello", "wamid.test123")
      )
      @gateway.call(context)
    end

    assert_equal 1, failed.length, "the refused send must be reported once"
    assert_equal 0, sent.length, "message.sent must not fire for a delivery the platform refused"
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
    assert_equal "", context.input
  end

  def test_post_request_media_message_processing
    context = create_context_with_request(
      method: :post,
      body: create_media_message_payload("media123", "image/jpeg", "wamid.media123")
    )

    @gateway.call(context)

    assert_equal :image, context["request.media"][:type]
    assert_equal "media123", context["request.media"][:id]
    assert_equal "image/jpeg", context["request.media"][:mime_type]
    assert_nil context["request.media"][:caption]
    assert_equal "+256700000000", context["request.msisdn"]
    assert_equal "wamid.media123", context["request.message_id"]
    assert_equal "", context.input
  end

  def test_post_request_video_message_processing
    context = create_context_with_request(
      method: :post,
      body: create_media_message_payload_for_type("video", "vid123", "video/mp4", "wamid.video123")
    )

    @gateway.call(context)

    assert_equal :video, context["request.media"][:type]
    assert_equal "vid123", context["request.media"][:id]
    assert_equal "video/mp4", context["request.media"][:mime_type]
    assert_equal "", context.input
  end

  def test_post_request_audio_message_processing
    context = create_context_with_request(
      method: :post,
      body: create_media_message_payload_for_type("audio", "aud123", "audio/ogg", "wamid.audio123")
    )

    @gateway.call(context)

    assert_equal :audio, context["request.media"][:type]
    assert_equal "aud123", context["request.media"][:id]
    assert_equal "audio/ogg", context["request.media"][:mime_type]
    assert_equal "", context.input
  end

  def test_post_request_document_message_processing
    context = create_context_with_request(
      method: :post,
      body: create_document_message_payload("doc123", "application/pdf", "report.pdf", "wamid.doc123")
    )

    @gateway.call(context)

    assert_equal :document, context["request.media"][:type]
    assert_equal "doc123", context["request.media"][:id]
    assert_equal "application/pdf", context["request.media"][:mime_type]
    assert_equal "report.pdf", context["request.media"][:filename]
    assert_equal "", context.input
  end

  def test_post_request_sticker_message_processing
    context = create_context_with_request(
      method: :post,
      body: create_sticker_message_payload("sticker123", "image/webp", false, "wamid.sticker123")
    )

    @gateway.call(context)

    assert_equal :sticker, context["request.media"][:type]
    assert_equal "sticker123", context["request.media"][:id]
    assert_equal "image/webp", context["request.media"][:mime_type]
    assert_equal false, context["request.media"][:animated]
    assert_equal "", context.input
  end

  def test_post_request_contact_message_processing
    context = create_context_with_request(
      method: :post,
      body: create_contact_message_payload("John Doe", "+1234567890", "wamid.contact123")
    )

    @gateway.call(context)

    assert_equal "John Doe", context["request.contact"][:name]
    assert_equal "+1234567890", context["request.contact"][:phone_number]
    assert_includes context["request.contact"][:phones], "+1234567890"
    assert_equal "+256700000000", context["request.msisdn"]
    assert_equal "wamid.contact123", context["request.message_id"]
    assert_equal "", context.input
  end

  def test_media_type_is_symbol_not_string
    # Verify media types are symbols for all media types
    %w[image video audio document sticker].each do |media_type|
      context = create_context_with_request(
        method: :post,
        body: create_media_message_payload_for_type(media_type, "test_id", "application/octet-stream", "wamid.#{media_type}")
      )

      # Create fresh gateway for each test to avoid state bleed
      gateway = FlowChat::Whatsapp::Gateway::CloudApi.new(proc { |ctx| [:text, "Response", nil, nil] }, @mock_config)
      gateway.call(context)

      assert_kind_of Symbol, context["request.media"][:type],
        "Expected media type to be Symbol for #{media_type}, got #{context["request.media"][:type].class}"
      assert_equal media_type.to_sym, context["request.media"][:type],
        "Expected :#{media_type} but got #{context["request.media"][:type].inspect}"
    end
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

  # --- Simulator mode ----------------------------------------------------
  #
  # The simulator's whole point is completing a turn with no live
  # credentials at hand, so it cannot be expected to send a phone_number_id
  # that matches a real configuration.

  def test_a_mismatched_phone_number_id_is_rejected_outside_simulator_mode
    context = create_context_with_request(
      method: :post,
      body: create_text_message_payload("Hello", "wamid.mismatch").tap { |p|
        p["entry"][0]["changes"][0]["value"]["metadata"]["phone_number_id"] = "not_the_configured_id"
      }
    )

    @gateway.call(context)

    assert_equal :forbidden, context.controller.last_head_status
  end

  def test_simulator_mode_completes_a_turn_despite_a_mismatched_phone_number_id
    with_simulator_secret do
      context = create_context_with_request(
        method: :post,
        body: create_text_message_payload("Hello", "wamid.sim").tap { |p|
          p["simulator_mode"] = true
          p["entry"][0]["changes"][0]["value"]["metadata"]["phone_number_id"] = "not_the_configured_id"
        },
        cookies: {FlowChat::Security::SIMULATOR_COOKIE_NAME => FlowChat::Security.simulator_cookie}
      )
      context["enable_simulator"] = true

      @gateway.call(context)

      assert_equal "Hello", context.input
      assert_equal "simulator", context.controller.last_render[:json][:mode]
    end
  end

  # The account check is skipped only once simulate? has already checked the
  # signed cookie - without one, simulator_mode param alone changes nothing.
  def test_simulator_mode_param_without_a_valid_cookie_is_still_rejected
    with_simulator_secret do
      context = create_context_with_request(
        method: :post,
        body: create_text_message_payload("Hello", "wamid.nocookie").tap { |p|
          p["simulator_mode"] = true
          p["entry"][0]["changes"][0]["value"]["metadata"]["phone_number_id"] = "not_the_configured_id"
        }
        # No simulator cookie set.
      )
      context["enable_simulator"] = true

      @gateway.call(context)

      assert_equal :forbidden, context.controller.last_head_status
    end
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

    # Should drop request silently (200 OK to prevent retries)
    assert_equal :ok, context.controller.last_head_status
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

    # Should drop request silently (200 OK to prevent retries)
    assert_equal :ok, context.controller.last_head_status
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

    # Should drop request silently (200 OK to prevent retries)
    assert_equal :ok, context.controller.last_head_status
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

    # Should drop request (signature doesn't match body) with 200 OK to prevent retries
    assert_equal :ok, context.controller.last_head_status
    assert_nil context.input
  end

  def test_verification_refuses_a_configuration_with_no_verify_token
    @mock_config.verify_token = nil

    context = create_context_with_request(
      method: :get,
      params: {"hub.mode" => "subscribe", "hub.challenge" => "claimed"}
    )

    @gateway.call(context)

    # Nothing configured means nothing to prove, so the challenge is refused rather
    # than answered by two missing tokens comparing equal.
    assert_equal :forbidden, context.controller.last_head_status
    assert_nil context.controller.last_render
  end

  def test_a_delivered_reply_names_its_platform_message_id
    context = create_context_with_request(
      method: :post,
      body: create_text_message_payload("Hello", "wamid.inbound")
    )

    @gateway.call(context)

    # The stubbed messages API answers with sent_123.
    assert_equal "sent_123", context[FlowChat::Instrumentation::DELIVERED_MESSAGE_ID_KEY]
  end

  # --- Webhook field dispatch -------------------------------------------------

  def test_dispatches_on_the_declared_field
    context = create_context_with_request(
      method: :post,
      body: create_text_message_payload("Hello", "wamid.field").tap { |p|
        p["entry"][0]["changes"][0]["field"] = "messages"
      }
    )

    @gateway.call(context)

    assert_equal "Hello", context.input
    assert_requested :post, @mock_config.messages_url
  end

  def test_an_unknown_field_is_accepted_and_ignored
    context = create_context_with_request(
      method: :post,
      body: change_payload("something_meta_added_later", {"whatever" => true})
    )

    @gateway.call(context)

    assert_equal :ok, context.controller.last_head_status
    assert_not_requested :post, @mock_config.messages_url
  end

  # Publishing is not much use if nothing says it happened. At debug this would be
  # invisible on a production log level.
  def test_a_published_field_is_named_in_the_log_at_info
    log = capture_logs do
      context = create_context_with_request(
        method: :post,
        body: change_payload("account_update", {"event" => "PARTNER_ADDED", "ban_info" => {}})
      )
      @gateway.call(context)
    end

    assert_includes log, "account_update"
    # Keys, so the shape is learnable without writing message content to a log.
    assert_includes log, "value keys:"
    assert_includes log, "ban_info"
  end

  def test_every_entry_and_change_is_looked_at
    statuses = change_payload("statuses", {"statuses" => [status_hash]})["entry"][0]["changes"][0]
    body = create_text_message_payload("Hello", "wamid.batched")
    # A status update ahead of the message, in its own entry, the way Meta batches.
    body["entry"].unshift({"changes" => [statuses]})

    seen = []
    subscribe(FlowChat::Instrumentation::Events::MESSAGE_STATUS) { |p| seen << p }

    context = create_context_with_request(method: :post, body: body)
    @gateway.call(context)

    assert_equal 1, seen.size, "the status ahead of the message must not be skipped"
    assert_equal "Hello", context.input, "the message behind the status must still run"
  end

  def test_a_second_messages_change_is_not_processed
    body = create_text_message_payload("First", "wamid.first")
    second = create_text_message_payload("Second", "wamid.second")["entry"][0]["changes"][0]
    body["entry"][0]["changes"] << second

    context = create_context_with_request(method: :post, body: body)
    @gateway.call(context)

    # Only one change can own the response, so the first wins and the rest are
    # reported rather than silently dropped.
    assert_equal "First", context.input
    assert_requested :post, @mock_config.messages_url, times: 1
  end

  # --- Statuses --------------------------------------------------------------

  # Meta has no `statuses` webhook field. A delivery report arrives as a change
  # whose field is `messages`, carrying statuses and no messages.
  def test_a_status_reported_under_the_messages_field_is_instrumented
    seen = nil
    subscribe(FlowChat::Instrumentation::Events::MESSAGE_STATUS) { |p| seen = p }

    context = create_context_with_request(
      method: :post,
      body: change_payload("messages", {"statuses" => [status_hash]})
    )
    @gateway.call(context)

    assert_equal "wamid.sent1", seen&.dig(:message_id)
    assert_not_requested :post, @mock_config.messages_url
    assert_equal :ok, context.controller.last_head_status
  end

  # The status must not spend the one flow slot a delivery has.
  def test_a_status_ahead_of_a_message_does_not_drop_the_message
    seen = nil
    subscribe(FlowChat::Instrumentation::Events::MESSAGE_STATUS) { |p| seen = p }

    body = create_text_message_payload("Hello", "wamid.behind_status")
    body["entry"][0]["changes"][0]["field"] = "messages"
    status_change = change_payload("messages", {"statuses" => [status_hash]})["entry"][0]["changes"][0]
    body["entry"][0]["changes"].unshift(status_change)

    context = create_context_with_request(method: :post, body: body)
    @gateway.call(context)

    assert_equal "wamid.sent1", seen&.dig(:message_id)
    assert_equal "Hello", context.input, "the message behind the status must still run"
    assert_requested :post, @mock_config.messages_url
  end

  def test_status_updates_are_instrumented
    seen = nil
    subscribe(FlowChat::Instrumentation::Events::MESSAGE_STATUS) { |p| seen = p }

    context = create_context_with_request(
      method: :post,
      body: change_payload("statuses", {"statuses" => [status_hash]})
    )
    @gateway.call(context)

    assert_equal "wamid.sent1", seen[:message_id]
    assert_equal "delivered", seen[:status]
    assert_equal "256700000000", seen[:recipient]
    assert_equal :whatsapp, seen[:platform]
    assert_equal :ok, context.controller.last_head_status
  end

  # A status says more than whether it arrived: what Meta billed the conversation
  # as, and its own view of the window. The named keys are what this gateway
  # promises, and the status itself is there for an application that wants the
  # rest without waiting on a release.
  def test_a_status_carries_what_the_named_keys_leave_out
    seen = nil
    subscribe(FlowChat::Instrumentation::Events::MESSAGE_STATUS) { |p| seen = p }

    status = status_hash.merge(
      "conversation" => {"id" => "conv-1", "origin" => {"type" => "service"}},
      "pricing" => {"billable" => true, "category" => "service"}
    )

    context = create_context_with_request(
      method: :post,
      body: change_payload("statuses", {"statuses" => [status]})
    )
    @gateway.call(context)

    assert_equal status, seen[:value]
    assert_equal "service", seen[:value].dig("pricing", "category")
  end

  # --- Everything that is not messaging --------------------------------------

  # Messaging is the gateway's job. Coexistence echoes, contact syncs, imported
  # history, account bans and template approvals are the application's, so they are
  # published whole rather than interpreted here.
  def test_a_field_that_is_not_messaging_is_published_whole
    seen = nil
    subscribe(FlowChat::Instrumentation::Events::WEBHOOK_RECEIVED) { |p| seen = p }

    echo = {
      "from" => "+15551234567",
      "to" => "256700000000",
      "id" => "wamid.echo1",
      "timestamp" => "1702891800",
      "type" => "text",
      "text" => {"body" => "Answered from the Business App"}
    }

    context = create_context_with_request(
      method: :post,
      body: change_payload("smb_message_echoes", {"message_echoes" => [echo]})
    )
    @gateway.call(context)

    assert_equal "smb_message_echoes", seen[:field]
    assert_equal [echo], seen[:value]["message_echoes"]
    assert_equal "test_phone_id", seen[:business_phone_number_id]
    assert_equal "waba-1", seen[:business_account_id]
    # An echo is the business talking, not a customer turn.
    assert_not_requested :post, @mock_config.messages_url
    assert_nil context.input
    assert_equal :ok, context.controller.last_head_status
  end

  # --- Echo origin -------------------------------------------------------
  #
  # An echo reports a message sent on the thread by someone other than the
  # user. Which someone decides what the application does with it, and only
  # this gateway knows our own app_id, so it derives the origin here rather
  # than leaving every subscriber to compare ids itself.

  def test_echo_from_a_human_in_the_business_inbox_has_no_app_id
    @mock_config.app_id = "our_app"
    events = []
    subscribe(FlowChat::Instrumentation::Events::WEBHOOK_RECEIVED) { |p| events << p }

    context = create_context_with_request(method: :post, body: echo_payload(app_id: nil))
    @gateway.call(context)

    assert_equal 1, events.size
    assert_equal :human_agent, events.first[:echo_origin]
  end

  def test_echo_from_our_own_app_carries_our_configured_app_id
    @mock_config.app_id = "our_app"
    events = []
    subscribe(FlowChat::Instrumentation::Events::WEBHOOK_RECEIVED) { |p| events << p }

    context = create_context_with_request(method: :post, body: echo_payload(app_id: "our_app"))
    @gateway.call(context)

    assert_equal :self, events.first[:echo_origin]
  end

  def test_echo_from_another_app_carries_a_different_app_id
    @mock_config.app_id = "our_app"
    events = []
    subscribe(FlowChat::Instrumentation::Events::WEBHOOK_RECEIVED) { |p| events << p }

    context = create_context_with_request(method: :post, body: echo_payload(app_id: "someone_else"))
    @gateway.call(context)

    assert_equal :other_app, events.first[:echo_origin]
  end

  def test_a_non_echo_field_carries_no_echo_origin_key_at_all
    events = []
    subscribe(FlowChat::Instrumentation::Events::WEBHOOK_RECEIVED) { |p| events << p }

    context = create_context_with_request(
      method: :post,
      body: change_payload("account_update", {"event" => "PARTNER_ADDED"})
    )
    @gateway.call(context)

    refute events.first.key?(:echo_origin)
  end

  # handle_unmodelled_field is the catch-all for every field Meta might send,
  # so a payload naming the echo field but shaped unexpectedly (no echoes
  # array, or an empty one) must not raise.
  def test_an_echo_field_with_no_echoes_array_is_treated_as_a_human_agent
    events = []
    subscribe(FlowChat::Instrumentation::Events::WEBHOOK_RECEIVED) { |p| events << p }

    context = create_context_with_request(
      method: :post,
      body: change_payload("smb_message_echoes", {})
    )
    @gateway.call(context)

    assert_equal :human_agent, events.first[:echo_origin]
  end

  def test_an_echo_field_with_an_empty_echoes_array_is_treated_as_a_human_agent
    events = []
    subscribe(FlowChat::Instrumentation::Events::WEBHOOK_RECEIVED) { |p| events << p }

    context = create_context_with_request(
      method: :post,
      body: change_payload("smb_message_echoes", {"message_echoes" => []})
    )
    @gateway.call(context)

    assert_equal :human_agent, events.first[:echo_origin]
  end

  def test_every_unmodelled_field_uses_the_same_event
    fields = {
      "smb_app_state_sync" => {"state_sync" => [{"type" => "contact"}]},
      "history" => {"history" => [{"threads" => []}]},
      "account_update" => {"event" => "DISABLED_UPDATE"},
      "message_template_status_update" => {"event" => "APPROVED"},
      "something_meta_adds_next_year" => {"whatever" => true}
    }

    seen = []
    subscribe(FlowChat::Instrumentation::Events::WEBHOOK_RECEIVED) { |p| seen << p }

    fields.each do |field, value|
      # A gateway parses its body once and keeps it, so each delivery needs its
      # own, the way a request gets its own in production.
      gateway = FlowChat::Whatsapp::Gateway::CloudApi.new(proc { |_| }, @mock_config)
      gateway.call(create_context_with_request(method: :post, body: change_payload(field, value)))
    end

    # No handler to add per field, which is the point: the gateway does not chase
    # Meta's field list.
    assert_equal fields.keys, seen.map { |p| p[:field] }
    assert_not_requested :post, @mock_config.messages_url
  end

  # A change about the account rather than one of its numbers carries no metadata,
  # so both phone number keys are empty. The account is the only thing naming who
  # it belongs to, and an application holding several businesses needs it.
  def test_an_account_level_field_is_published_with_the_account_that_owns_it
    seen = nil
    subscribe(FlowChat::Instrumentation::Events::WEBHOOK_RECEIVED) { |p| seen = p }

    body = {
      "entry" => [{
        "id" => "waba-1",
        "changes" => [{
          "field" => "account_update",
          "value" => {"event" => "DISABLED_UPDATE", "ban_info" => {"waba_ban_state" => "SCHEDULE_FOR_DISABLE"}}
        }]
      }]
    }

    @gateway.call(create_context_with_request(method: :post, body: body))

    assert_equal "waba-1", seen[:business_account_id]
    assert_nil seen[:business_phone_number_id]
    assert_nil seen[:business_phone_number]
  end

  def test_a_declined_history_import_is_published_too
    seen = nil
    subscribe(FlowChat::Instrumentation::Events::WEBHOOK_RECEIVED) { |p| seen = p }

    history = [{"errors" => [{"code" => 2593109, "title" => "History sync is turned off"}]}]

    context = create_context_with_request(
      method: :post,
      body: change_payload("history", {"history" => history})
    )
    @gateway.call(context)

    # A refusal is news too: the application has to stop waiting for the import.
    assert_equal history, seen[:value]["history"]
  end

  private

  def with_simulator_secret
    original = FlowChat::Config.simulator_secret
    FlowChat::Config.simulator_secret = "test_simulator_secret"
    yield
  ensure
    FlowChat::Config.simulator_secret = original
  end

  # Captures at info level on purpose: a message logged at debug would not appear,
  # which is the regression this guards.
  def capture_logs
    original = FlowChat::Config.logger
    io = StringIO.new
    FlowChat::Config.logger = Logger.new(io, level: :info)
    yield
    io.string
  ensure
    FlowChat::Config.logger = original
  end

  def subscribe(event)
    @subscribers ||= []
    @subscribers << ActiveSupport::Notifications.subscribe("#{event}.flow_chat") do |*args|
      yield ActiveSupport::Notifications::Event.new(*args).payload
    end
  end

  def status_hash
    {
      "id" => "wamid.sent1",
      "status" => "delivered",
      "recipient_id" => "256700000000",
      "timestamp" => "1702891800"
    }
  end

  # A single-change delivery for a named field.
  def change_payload(field, value)
    {
      "entry" => [{
        "id" => "waba-1",
        "changes" => [{
          "field" => field,
          "value" => {
            "messaging_product" => "whatsapp",
            "metadata" => {
              "display_phone_number" => "+15551234567",
              "phone_number_id" => "test_phone_id"
            }
          }.merge(value)
        }]
      }]
    }
  end

  # A coexistence echo for the same message, with a caller-chosen sender app_id
  # (or none, for a human replying from the business inbox).
  def echo_payload(app_id:)
    echo = {"id" => "wamid.echo1", "from" => "15551234567", "type" => "text", "text" => {"body" => "Hi"}}
    echo["app_id"] = app_id if app_id

    change_payload("smb_message_echoes", {"message_echoes" => [echo]})
  end

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
            "messaging_product" => "whatsapp",
            "metadata" => {
              "display_phone_number" => "+15551234567",
              "phone_number_id" => "test_phone_id"
            },
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
            "messaging_product" => "whatsapp",
            "metadata" => {
              "display_phone_number" => "+15551234567",
              "phone_number_id" => "test_phone_id"
            },
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
            "messaging_product" => "whatsapp",
            "metadata" => {
              "display_phone_number" => "+15551234567",
              "phone_number_id" => "test_phone_id"
            },
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
            "messaging_product" => "whatsapp",
            "metadata" => {
              "display_phone_number" => "+15551234567",
              "phone_number_id" => "test_phone_id"
            },
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
    create_media_message_payload_for_type("image", media_id, mime_type, message_id)
  end

  def create_media_message_payload_for_type(type, media_id, mime_type, message_id)
    {
      "entry" => [{
        "changes" => [{
          "value" => {
            "messaging_product" => "whatsapp",
            "metadata" => {
              "display_phone_number" => "+15551234567",
              "phone_number_id" => "test_phone_id"
            },
            "messages" => [{
              "id" => message_id,
              "from" => "256700000000",
              "timestamp" => "1702891800",
              type => {
                "id" => media_id,
                "mime_type" => mime_type
              },
              "type" => type
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

  def create_document_message_payload(media_id, mime_type, filename, message_id)
    {
      "entry" => [{
        "changes" => [{
          "value" => {
            "messaging_product" => "whatsapp",
            "metadata" => {
              "display_phone_number" => "+15551234567",
              "phone_number_id" => "test_phone_id"
            },
            "messages" => [{
              "id" => message_id,
              "from" => "256700000000",
              "timestamp" => "1702891800",
              "document" => {
                "id" => media_id,
                "mime_type" => mime_type,
                "filename" => filename
              },
              "type" => "document"
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

  def create_sticker_message_payload(media_id, mime_type, animated, message_id)
    {
      "entry" => [{
        "changes" => [{
          "value" => {
            "messaging_product" => "whatsapp",
            "metadata" => {
              "display_phone_number" => "+15551234567",
              "phone_number_id" => "test_phone_id"
            },
            "messages" => [{
              "id" => message_id,
              "from" => "256700000000",
              "timestamp" => "1702891800",
              "sticker" => {
                "id" => media_id,
                "mime_type" => mime_type,
                "animated" => animated
              },
              "type" => "sticker"
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

  def create_contact_message_payload(name, phone_number, message_id)
    {
      "entry" => [{
        "changes" => [{
          "value" => {
            "messaging_product" => "whatsapp",
            "metadata" => {
              "display_phone_number" => "+15551234567",
              "phone_number_id" => "test_phone_id"
            },
            "messages" => [{
              "id" => message_id,
              "from" => "256700000000",
              "timestamp" => "1702891800",
              "contacts" => [{
                "name" => {
                  "formatted_name" => name,
                  "first_name" => name.split.first,
                  "last_name" => name.split.last
                },
                "phones" => [{"phone" => phone_number, "type" => "MOBILE"}]
              }],
              "type" => "contacts"
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
            "messaging_product" => "whatsapp",
            "metadata" => {
              "display_phone_number" => "+15551234567",
              "phone_number_id" => "test_phone_id"
            },
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

  def test_sets_request_body_with_stringified_keys
    webhook_payload = create_text_message_payload("Test message", "wamid.test999")

    context = create_context_with_request(
      method: :post,
      body: webhook_payload
    )

    @gateway.call(context)

    # Verify request.body is set
    assert_kind_of Hash, context["request.body"]

    # Verify it contains the expected webhook structure
    assert context["request.body"]["entry"]
    assert_kind_of Array, context["request.body"]["entry"]

    # Verify nested structure has string keys
    entry = context["request.body"]["entry"].first
    assert_kind_of Hash, entry
    assert entry["changes"]

    # Verify all top-level keys are strings
    context["request.body"].keys.each do |key|
      assert_kind_of String, key, "Expected all keys to be strings, but found #{key.class}"
    end

    # Verify nested keys are also strings
    entry.keys.each do |key|
      assert_kind_of String, key, "Expected nested keys to be strings, but found #{key.class}"
    end
  end
end

class WhatsappCloudApiGatewayMiddlewareStackTest < Minitest::Test
  def test_configure_middleware_stack_adds_choice_mapper
    # Create a mock builder to track middleware registration
    builder = MockMiddlewareBuilder.new
    custom_middleware = Object.new

    # Call the class method
    FlowChat::Whatsapp::Gateway::CloudApi.configure_middleware_stack(builder, custom_middleware)

    # Verify custom middleware was added first
    assert_equal custom_middleware, builder.middlewares[0],
      "Custom middleware should be added first"

    # Verify ChoiceMapper was added second
    assert_equal FlowChat::Whatsapp::Middleware::ChoiceMapper, builder.middlewares[1],
      "ChoiceMapper should be added after custom middleware"
  end

  def test_configure_middleware_stack_order_matches_ussd_pattern
    # WhatsApp should follow same pattern as USSD: custom middleware -> platform middleware
    builder = MockMiddlewareBuilder.new
    custom_middleware = Object.new

    FlowChat::Whatsapp::Gateway::CloudApi.configure_middleware_stack(builder, custom_middleware)

    # Verify order: custom first, then ChoiceMapper
    assert_equal 2, builder.middlewares.length,
      "Should have exactly 2 middlewares registered"
    assert_equal custom_middleware, builder.middlewares[0]
    assert_equal FlowChat::Whatsapp::Middleware::ChoiceMapper, builder.middlewares[1]
  end

  # Mock builder to track middleware registration
  class MockMiddlewareBuilder
    attr_reader :middlewares

    def initialize
      @middlewares = []
    end

    def use(middleware, *args)
      @middlewares << middleware
    end
  end
end

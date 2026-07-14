require "test_helper"
require "webmock/minitest"

class FlowChat::Telegram::Gateway::BotApiTest < Minitest::Test
  def setup
    @mock_config = FlowChat::Telegram::Configuration.new("test_config")
    @mock_config.bot_token = "123456:ABC-DEF1234ghIkl"
    @mock_config.secret_token = "test_secret_token"

    @gateway = FlowChat::Telegram::Gateway::BotApi.new(
      proc { |context| [:text, "Response", nil, nil] },
      @mock_config
    )

    WebMock.enable!
    WebMock.reset!

    # Stub the Telegram sendMessage API
    stub_request(:post, "https://api.telegram.org/bot123456:ABC-DEF1234ghIkl/sendMessage")
      .to_return(status: 200, body: {"ok" => true, "result" => {"message_id" => 123}}.to_json)

    # Stub answerCallbackQuery
    stub_request(:post, "https://api.telegram.org/bot123456:ABC-DEF1234ghIkl/answerCallbackQuery")
      .to_return(status: 200, body: {"ok" => true}.to_json)
  end

  def teardown
    WebMock.disable!
    WebMock.reset!
  end

  # ============================================================================
  # REQUEST METHOD TESTS
  # ============================================================================

  def test_non_post_request_returns_bad_request
    context = create_context_with_request(method: :get)

    @gateway.call(context)

    assert_equal :bad_request, context.controller.last_head_status
  end

  def test_put_request_returns_bad_request
    context = create_context_with_request(method: :put)

    @gateway.call(context)

    assert_equal :bad_request, context.controller.last_head_status
  end

  # ============================================================================
  # TEXT MESSAGE PROCESSING TESTS
  # ============================================================================

  def test_post_request_text_message_processing
    context = create_context_with_request(
      method: :post,
      body: create_text_message_payload("Hello bot!", 12345)
    )

    @gateway.call(context)

    assert_equal "Hello bot!", context.input
    assert_equal "987654321", context["request.id"]
    assert_equal "123456789", context["request.user_id"]
    assert_equal "John Doe", context["request.user_name"]
    assert_equal "johndoe", context["request.username"]
    assert_equal :telegram_bot_api, context["request.gateway"]
    assert_equal :telegram, context["request.platform"]
    assert_equal "12345", context["request.message_id"]
    assert_equal "private", context["telegram.chat_type"]
  end

  def test_post_request_text_message_with_bot_command
    context = create_context_with_request(
      method: :post,
      body: create_text_message_payload("/start", 12345)
    )

    @gateway.call(context)

    assert_equal "/start", context.input
  end

  # ============================================================================
  # CALLBACK QUERY (BUTTON PRESS) TESTS
  # ============================================================================

  def test_post_request_callback_query_processing
    context = create_context_with_request(
      method: :post,
      body: create_callback_query_payload("btn_1", "callback_123")
    )

    @gateway.call(context)

    assert_equal "btn_1", context.input
    assert_equal "987654321", context["request.id"]
    assert_equal "123456789", context["request.user_id"]
    assert_equal "callback_123", context["telegram.callback_query_id"]
    assert_equal 99999, context["telegram.original_message_id"]
  end

  def test_callback_query_auto_answers
    context = create_context_with_request(
      method: :post,
      body: create_callback_query_payload("btn_1", "callback_123")
    )

    @gateway.call(context)

    # Verify answerCallbackQuery was called
    assert_requested :post, "https://api.telegram.org/bot123456:ABC-DEF1234ghIkl/answerCallbackQuery"
  end

  # ============================================================================
  # LOCATION MESSAGE TESTS
  # ============================================================================

  def test_post_request_location_message_processing
    context = create_context_with_request(
      method: :post,
      body: create_location_message_payload(51.5074, -0.1278, 12346)
    )

    @gateway.call(context)

    assert_equal "", context.input
    expected_location = {
      "latitude" => 51.5074,
      "longitude" => -0.1278
    }
    assert_equal expected_location, context["request.location"]
  end

  # ============================================================================
  # MEDIA MESSAGE TESTS
  # ============================================================================

  def test_post_request_photo_message_processing
    context = create_context_with_request(
      method: :post,
      body: create_photo_message_payload("AgACAgIAAxkBAAI", 12347)
    )

    @gateway.call(context)

    assert_equal "", context.input
    assert_equal :photo, context["request.media"][:type]
    assert_equal "AgACAgIAAxkBAAI", context["request.media"][:file_id]
  end

  def test_caption_less_media_still_instruments_message_received
    context = create_context_with_request(
      method: :post,
      body: create_photo_message_payload("AgACAgIAAxkBAAI", 12347)
    )

    events = []
    ActiveSupport::Notifications.subscribe("message.received.flow_chat") { |e| events << e }
    @gateway.call(context)

    assert_equal 1, events.size, "a caption-less photo must still emit MESSAGE_RECEIVED"
    assert_equal "photo", events.first.payload[:message_type]
  ensure
    ActiveSupport::Notifications.unsubscribe("message.received.flow_chat")
  end

  def test_post_request_photo_message_captures_caption
    payload = create_photo_message_payload("AgACAgIAAxkBAAI", 12347)
    payload["message"]["caption"] = "my caption"

    context = create_context_with_request(
      method: :post,
      body: payload
    )

    @gateway.call(context)

    # The caption becomes the turn's text (input); no sentinel when text is present.
    assert_equal "my caption", context.input
    assert_equal :photo, context["request.media"][:type]
    assert_equal "my caption", context["request.media"][:caption]
  end

  def test_post_request_document_message_processing
    context = create_context_with_request(
      method: :post,
      body: create_document_message_payload("BQACAgIAAxkBAAI", "report.pdf", "application/pdf", 12348)
    )

    @gateway.call(context)

    assert_equal "", context.input
    assert_equal :document, context["request.media"][:type]
    assert_equal "BQACAgIAAxkBAAI", context["request.media"][:file_id]
    assert_equal "report.pdf", context["request.media"][:file_name]
    assert_equal "application/pdf", context["request.media"][:mime_type]
  end

  def test_post_request_voice_message_processing
    context = create_context_with_request(
      method: :post,
      body: create_voice_message_payload("AwACAgIAAxkBAAI", 10, 12349)
    )

    @gateway.call(context)

    assert_equal "", context.input
    assert_equal :voice, context["request.media"][:type]
    assert_equal "AwACAgIAAxkBAAI", context["request.media"][:file_id]
    assert_equal 10, context["request.media"][:duration]
  end

  # ============================================================================
  # CONTACT MESSAGE TESTS
  # ============================================================================

  def test_post_request_contact_message_processing
    context = create_context_with_request(
      method: :post,
      body: create_contact_message_payload("+15551234567", "Jane", "Doe", 12350)
    )

    @gateway.call(context)

    assert_equal "", context.input
    assert_equal "+15551234567", context["request.contact"][:phone_number]
    assert_equal "Jane", context["request.contact"][:first_name]
    assert_equal "Doe", context["request.contact"][:last_name]
  end

  # ============================================================================
  # WEBHOOK PAYLOAD HANDLING TESTS
  # ============================================================================

  def test_empty_webhook_payload_handling
    context = create_context_with_request(
      method: :post,
      body: "{}"
    )

    @gateway.call(context)

    assert_equal :ok, context.controller.last_head_status
  end

  def test_malformed_webhook_payload_handling
    context = create_context_with_request(
      method: :post,
      body: "invalid json {"
    )

    @gateway.call(context)

    assert_equal :bad_request, context.controller.last_head_status
  end

  def test_unsupported_update_type_handling
    context = create_context_with_request(
      method: :post,
      body: {
        "update_id" => 123456,
        "poll" => {"id" => "123", "question" => "Test poll"}
      }.to_json
    )

    @gateway.call(context)

    # Should return OK but not process
    assert_equal :ok, context.controller.last_head_status
  end

  # ============================================================================
  # WEBHOOK SIGNATURE VALIDATION TESTS
  # ============================================================================

  def test_valid_webhook_signature
    context = create_context_with_request(
      method: :post,
      body: create_text_message_payload("Hello", 12345),
      headers: {
        "X-Telegram-Bot-Api-Secret-Token" => "test_secret_token"
      }
    )

    @gateway.call(context)

    # Should process successfully with valid signature
    assert_equal "Hello", context.input
    assert_equal :ok, context.controller.last_head_status
  end

  def test_invalid_webhook_signature
    context = create_context_with_request(
      method: :post,
      body: create_text_message_payload("Hello", 12345),
      headers: {
        "X-Telegram-Bot-Api-Secret-Token" => "wrong_secret"
      }
    )

    @gateway.call(context)

    assert_equal :ok, context.controller.last_head_status
    assert_nil context.input
  end

  def test_missing_webhook_signature_header
    context = create_context_with_request(
      method: :post,
      body: create_text_message_payload("Hello", 12345),
      headers: {skip_auto_signature: true}  # Skip auto-signature to test missing header
    )

    @gateway.call(context)

    assert_equal :ok, context.controller.last_head_status
    assert_nil context.input
  end

  def test_webhook_validation_skipped_without_secret_token
    @mock_config.secret_token = nil

    context = create_context_with_request(
      method: :post,
      body: create_text_message_payload("Hello", 12345),
      headers: {}
    )

    @gateway.call(context)

    # Should process successfully when no secret_token configured
    assert_equal "Hello", context.input
    assert_equal :ok, context.controller.last_head_status
  end

  def test_webhook_validation_explicitly_disabled
    @mock_config.secret_token = "test_secret"
    @mock_config.skip_signature_validation = true

    context = create_context_with_request(
      method: :post,
      body: create_text_message_payload("Hello", 12345),
      headers: {
        "X-Telegram-Bot-Api-Secret-Token" => "completely_wrong"
      }
    )

    @gateway.call(context)

    # Should process successfully when validation is disabled
    assert_equal "Hello", context.input
    assert_equal :ok, context.controller.last_head_status
  end

  # ============================================================================
  # SECURE COMPARE TESTS
  # ============================================================================

  def test_secure_compare_equal_strings
    result = @gateway.send(:secure_compare, "hello", "hello")
    assert_equal true, result
  end

  def test_secure_compare_different_strings
    result = @gateway.send(:secure_compare, "hello", "world")
    assert_equal false, result
  end

  def test_secure_compare_different_lengths
    result = @gateway.send(:secure_compare, "hello", "hi")
    assert_equal false, result
  end

  def test_secure_compare_empty_strings
    assert @gateway.send(:secure_compare, "", "")
    refute @gateway.send(:secure_compare, "", "hello")
  end

  # ============================================================================
  # GROUP CHAT TESTS
  # ============================================================================

  def test_group_chat_message
    context = create_context_with_request(
      method: :post,
      body: create_group_message_payload("Hello group!", 12351, -100123456789)
    )

    @gateway.call(context)

    assert_equal "Hello group!", context.input
    assert_equal "-100123456789", context["request.id"]
    assert_equal "group", context["telegram.chat_type"]
  end

  def test_supergroup_chat_message
    payload = create_group_message_payload("Hello!", 12352, -100987654321)
    payload["message"]["chat"]["type"] = "supergroup"

    context = create_context_with_request(
      method: :post,
      body: payload.to_json
    )

    @gateway.call(context)

    assert_equal "supergroup", context["telegram.chat_type"]
  end

  # ============================================================================
  # CONTEXT REQUEST.BODY TESTS
  # ============================================================================

  def test_sets_request_body_with_stringified_keys
    webhook_payload = create_text_message_payload("Test message", 12345)

    context = create_context_with_request(
      method: :post,
      body: webhook_payload
    )

    @gateway.call(context)

    # Verify request.body is set
    assert_kind_of Hash, context["request.body"]

    # Verify it contains the expected webhook structure
    assert context["request.body"]["update_id"]
    assert context["request.body"]["message"]

    # Verify all top-level keys are strings
    context["request.body"].keys.each do |key|
      assert_kind_of String, key, "Expected all keys to be strings, but found #{key.class}"
    end
  end

  private

  def create_context_with_request(method:, params: {}, body: nil, headers: {})
    context = FlowChat::Context.new

    # Auto-add secret token header if not explicitly provided and not testing signature failure
    if body && @mock_config.secret_token && !headers.key?("X-Telegram-Bot-Api-Secret-Token") && !headers.key?(:skip_auto_signature)
      headers["X-Telegram-Bot-Api-Secret-Token"] = @mock_config.secret_token
    end

    headers.delete(:skip_auto_signature)

    # Create mock request
    request = OpenStruct.new(params: params, headers: headers)
    request.define_singleton_method(:get?) { method == :get }
    request.define_singleton_method(:post?) { method == :post }
    request.define_singleton_method(:head?) { method == :head }

    if body
      request.define_singleton_method(:body) do
        StringIO.new(body.is_a?(String) ? body : body.to_json)
      end
    end

    # Create mock controller
    controller = OpenStruct.new(request: request)

    mock_response = FlowChat::TestSupport::MockResponse.new
    controller.define_singleton_method(:response) { mock_response }

    controller.define_singleton_method(:render) do |options|
      @last_render = options
    end
    controller.define_singleton_method(:last_render) { @last_render }

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
      "update_id" => 123456789,
      "message" => {
        "message_id" => message_id,
        "from" => {
          "id" => 123456789,
          "is_bot" => false,
          "first_name" => "John",
          "last_name" => "Doe",
          "username" => "johndoe",
          "language_code" => "en"
        },
        "chat" => {
          "id" => 987654321,
          "first_name" => "John",
          "last_name" => "Doe",
          "username" => "johndoe",
          "type" => "private"
        },
        "date" => 1702891800,
        "text" => text
      }
    }
  end

  def create_callback_query_payload(callback_data, callback_query_id)
    {
      "update_id" => 123456790,
      "callback_query" => {
        "id" => callback_query_id,
        "from" => {
          "id" => 123456789,
          "is_bot" => false,
          "first_name" => "John",
          "last_name" => "Doe",
          "username" => "johndoe",
          "language_code" => "en"
        },
        "message" => {
          "message_id" => 99999,
          "from" => {
            "id" => 987654321,
            "is_bot" => true,
            "first_name" => "TestBot"
          },
          "chat" => {
            "id" => 987654321,
            "first_name" => "John",
            "last_name" => "Doe",
            "type" => "private"
          },
          "date" => 1702891700,
          "text" => "Choose an option:"
        },
        "chat_instance" => "-1234567890",
        "data" => callback_data
      }
    }
  end

  def create_location_message_payload(latitude, longitude, message_id)
    {
      "update_id" => 123456791,
      "message" => {
        "message_id" => message_id,
        "from" => {
          "id" => 123456789,
          "is_bot" => false,
          "first_name" => "John",
          "last_name" => "Doe",
          "username" => "johndoe"
        },
        "chat" => {
          "id" => 987654321,
          "first_name" => "John",
          "type" => "private"
        },
        "date" => 1702891800,
        "location" => {
          "latitude" => latitude,
          "longitude" => longitude
        }
      }
    }
  end

  def create_photo_message_payload(file_id, message_id)
    {
      "update_id" => 123456792,
      "message" => {
        "message_id" => message_id,
        "from" => {
          "id" => 123456789,
          "is_bot" => false,
          "first_name" => "John",
          "username" => "johndoe"
        },
        "chat" => {
          "id" => 987654321,
          "first_name" => "John",
          "type" => "private"
        },
        "date" => 1702891800,
        "photo" => [
          {"file_id" => "small_id", "file_unique_id" => "small", "width" => 90, "height" => 90},
          {"file_id" => "medium_id", "file_unique_id" => "medium", "width" => 320, "height" => 320},
          {"file_id" => file_id, "file_unique_id" => "large", "width" => 800, "height" => 800}
        ]
      }
    }
  end

  def create_document_message_payload(file_id, file_name, mime_type, message_id)
    {
      "update_id" => 123456793,
      "message" => {
        "message_id" => message_id,
        "from" => {
          "id" => 123456789,
          "is_bot" => false,
          "first_name" => "John",
          "username" => "johndoe"
        },
        "chat" => {
          "id" => 987654321,
          "first_name" => "John",
          "type" => "private"
        },
        "date" => 1702891800,
        "document" => {
          "file_id" => file_id,
          "file_unique_id" => "unique_doc",
          "file_name" => file_name,
          "mime_type" => mime_type,
          "file_size" => 12345
        }
      }
    }
  end

  def create_voice_message_payload(file_id, duration, message_id)
    {
      "update_id" => 123456794,
      "message" => {
        "message_id" => message_id,
        "from" => {
          "id" => 123456789,
          "is_bot" => false,
          "first_name" => "John",
          "username" => "johndoe"
        },
        "chat" => {
          "id" => 987654321,
          "first_name" => "John",
          "type" => "private"
        },
        "date" => 1702891800,
        "voice" => {
          "file_id" => file_id,
          "file_unique_id" => "unique_voice",
          "duration" => duration,
          "mime_type" => "audio/ogg"
        }
      }
    }
  end

  def create_contact_message_payload(phone_number, first_name, last_name, message_id)
    {
      "update_id" => 123456795,
      "message" => {
        "message_id" => message_id,
        "from" => {
          "id" => 123456789,
          "is_bot" => false,
          "first_name" => "John",
          "username" => "johndoe"
        },
        "chat" => {
          "id" => 987654321,
          "first_name" => "John",
          "type" => "private"
        },
        "date" => 1702891800,
        "contact" => {
          "phone_number" => phone_number,
          "first_name" => first_name,
          "last_name" => last_name,
          "user_id" => 111222333
        }
      }
    }
  end

  def create_group_message_payload(text, message_id, chat_id)
    {
      "update_id" => 123456796,
      "message" => {
        "message_id" => message_id,
        "from" => {
          "id" => 123456789,
          "is_bot" => false,
          "first_name" => "John",
          "username" => "johndoe"
        },
        "chat" => {
          "id" => chat_id,
          "title" => "Test Group",
          "type" => "group"
        },
        "date" => 1702891800,
        "text" => text
      }
    }
  end
end

class FlowChat::Telegram::Gateway::BotApiMiddlewareStackTest < Minitest::Test
  def test_configure_middleware_stack_adds_choice_mapper
    builder = MockMiddlewareBuilder.new
    custom_middleware = Object.new

    FlowChat::Telegram::Gateway::BotApi.configure_middleware_stack(builder, custom_middleware)

    assert_equal custom_middleware, builder.middlewares[0],
      "Custom middleware should be added first"

    assert_equal FlowChat::Telegram::Middleware::ChoiceMapper, builder.middlewares[1],
      "ChoiceMapper should be added after custom middleware"
  end

  def test_configure_middleware_stack_order
    builder = MockMiddlewareBuilder.new
    custom_middleware = Object.new

    FlowChat::Telegram::Gateway::BotApi.configure_middleware_stack(builder, custom_middleware)

    assert_equal 2, builder.middlewares.length,
      "Should have exactly 2 middlewares registered"
  end

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

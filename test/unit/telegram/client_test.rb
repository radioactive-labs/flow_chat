require "test_helper"
require "webmock/minitest"

class FlowChat::Telegram::ClientTest < Minitest::Test
  def setup
    @config = FlowChat::Telegram::Configuration.new("test")
    @config.bot_token = "123456:ABC-DEF1234ghIkl"

    @client = FlowChat::Telegram::Client.new(@config)

    WebMock.enable!
    WebMock.reset!
  end

  def teardown
    WebMock.disable!
    WebMock.reset!
  end

  # ============================================================================
  # SEND TEXT MESSAGE TESTS
  # ============================================================================

  def test_send_text_message
    stub_request(:post, "https://api.telegram.org/bot123456:ABC-DEF1234ghIkl/sendMessage")
      .with(
        body: hash_including(
          "chat_id" => 12345,
          "text" => "Hello World"
        )
      )
      .to_return(
        status: 200,
        body: {
          "ok" => true,
          "result" => {"message_id" => 123, "chat" => {"id" => 12345}}
        }.to_json
      )

    result = @client.send_text(12345, "Hello World")

    assert result["ok"]
    assert_equal 123, result["result"]["message_id"]
  end

  def test_send_text_with_parse_mode
    stub_request(:post, "https://api.telegram.org/bot123456:ABC-DEF1234ghIkl/sendMessage")
      .with(
        body: hash_including(
          "chat_id" => 12345,
          "text" => "<b>Bold</b>",
          "parse_mode" => "HTML"
        )
      )
      .to_return(status: 200, body: {"ok" => true, "result" => {}}.to_json)

    result = @client.send_text(12345, "<b>Bold</b>", parse_mode: "HTML")

    assert result["ok"]
  end

  def test_send_text_with_markdown
    stub_request(:post, "https://api.telegram.org/bot123456:ABC-DEF1234ghIkl/sendMessage")
      .with(
        body: hash_including(
          "parse_mode" => "MarkdownV2"
        )
      )
      .to_return(status: 200, body: {"ok" => true, "result" => {}}.to_json)

    result = @client.send_text(12345, "*Bold*", parse_mode: "MarkdownV2")

    assert result["ok"]
  end

  # ============================================================================
  # SEND MESSAGE (UNIFIED) TESTS
  # ============================================================================

  def test_send_message_text_only
    stub_request(:post, "https://api.telegram.org/bot123456:ABC-DEF1234ghIkl/sendMessage")
      .to_return(status: 200, body: {"ok" => true, "result" => {}}.to_json)

    result = @client.send_message(12345, "Hello")

    assert result["ok"]
    assert_requested :post, "https://api.telegram.org/bot123456:ABC-DEF1234ghIkl/sendMessage"
  end

  def test_send_message_with_choices
    stub_request(:post, "https://api.telegram.org/bot123456:ABC-DEF1234ghIkl/sendMessage")
      .with(
        body: hash_including("reply_markup")
      )
      .to_return(status: 200, body: {"ok" => true, "result" => {}}.to_json)

    choices = {"opt1" => "Option 1", "opt2" => "Option 2"}
    result = @client.send_message(12345, "Choose:", choices: choices)

    assert result["ok"]
  end

  def test_send_message_with_photo_media
    stub_request(:post, "https://api.telegram.org/bot123456:ABC-DEF1234ghIkl/sendPhoto")
      .with(
        body: hash_including(
          "chat_id" => 12345,
          "photo" => "https://example.com/image.jpg",
          "caption" => "Look at this"
        )
      )
      .to_return(status: 200, body: {"ok" => true, "result" => {}}.to_json)

    media = {type: :photo, url: "https://example.com/image.jpg"}
    result = @client.send_message(12345, "Look at this", media: media)

    assert result["ok"]
  end

  # ============================================================================
  # SEND TEXT WITH KEYBOARD TESTS
  # ============================================================================

  def test_send_text_with_inline_keyboard
    keyboard = [[{text: "Button 1", callback_data: "btn1"}]]

    stub_request(:post, "https://api.telegram.org/bot123456:ABC-DEF1234ghIkl/sendMessage")
      .with { |request|
        body = JSON.parse(request.body)
        body["chat_id"] == 12345 &&
          body["text"] == "Choose:" &&
          body["reply_markup"]["inline_keyboard"].is_a?(Array)
      }
      .to_return(status: 200, body: {"ok" => true, "result" => {}}.to_json)

    result = @client.send_text_with_keyboard(12345, "Choose:", keyboard)

    assert result["ok"]
  end

  # ============================================================================
  # SEND MEDIA TESTS
  # ============================================================================

  def test_send_photo_with_url
    stub_request(:post, "https://api.telegram.org/bot123456:ABC-DEF1234ghIkl/sendPhoto")
      .with(
        body: hash_including(
          "chat_id" => 12345,
          "photo" => "https://example.com/photo.jpg",
          "caption" => "Nice photo"
        )
      )
      .to_return(status: 200, body: {"ok" => true, "result" => {}}.to_json)

    result = @client.send_photo(12345, "https://example.com/photo.jpg", caption: "Nice photo")

    assert result["ok"]
  end

  def test_send_photo_with_file_id
    stub_request(:post, "https://api.telegram.org/bot123456:ABC-DEF1234ghIkl/sendPhoto")
      .with(
        body: hash_including(
          "photo" => "AgACAgIAAxkBAAI"
        )
      )
      .to_return(status: 200, body: {"ok" => true, "result" => {}}.to_json)

    result = @client.send_photo(12345, "AgACAgIAAxkBAAI")

    assert result["ok"]
  end

  def test_send_document
    stub_request(:post, "https://api.telegram.org/bot123456:ABC-DEF1234ghIkl/sendDocument")
      .with(
        body: hash_including(
          "chat_id" => 12345,
          "document" => "https://example.com/doc.pdf",
          "caption" => "Report"
        )
      )
      .to_return(status: 200, body: {"ok" => true, "result" => {}}.to_json)

    result = @client.send_document(12345, "https://example.com/doc.pdf", caption: "Report")

    assert result["ok"]
  end

  def test_send_video
    stub_request(:post, "https://api.telegram.org/bot123456:ABC-DEF1234ghIkl/sendVideo")
      .with(
        body: hash_including(
          "chat_id" => 12345,
          "video" => "https://example.com/video.mp4"
        )
      )
      .to_return(status: 200, body: {"ok" => true, "result" => {}}.to_json)

    result = @client.send_video(12345, "https://example.com/video.mp4")

    assert result["ok"]
  end

  def test_send_audio
    stub_request(:post, "https://api.telegram.org/bot123456:ABC-DEF1234ghIkl/sendAudio")
      .with(
        body: hash_including(
          "chat_id" => 12345,
          "audio" => "https://example.com/audio.mp3"
        )
      )
      .to_return(status: 200, body: {"ok" => true, "result" => {}}.to_json)

    result = @client.send_audio(12345, "https://example.com/audio.mp3")

    assert result["ok"]
  end

  def test_send_voice
    stub_request(:post, "https://api.telegram.org/bot123456:ABC-DEF1234ghIkl/sendVoice")
      .with(
        body: hash_including(
          "chat_id" => 12345,
          "voice" => "https://example.com/voice.ogg"
        )
      )
      .to_return(status: 200, body: {"ok" => true, "result" => {}}.to_json)

    result = @client.send_voice(12345, "https://example.com/voice.ogg")

    assert result["ok"]
  end

  # ============================================================================
  # CALLBACK QUERY TESTS
  # ============================================================================

  def test_answer_callback_query
    stub_request(:post, "https://api.telegram.org/bot123456:ABC-DEF1234ghIkl/answerCallbackQuery")
      .with(
        body: hash_including(
          "callback_query_id" => "query123"
        )
      )
      .to_return(status: 200, body: {"ok" => true, "result" => true}.to_json)

    result = @client.answer_callback_query("query123")

    assert result["ok"]
  end

  def test_answer_callback_query_with_text
    stub_request(:post, "https://api.telegram.org/bot123456:ABC-DEF1234ghIkl/answerCallbackQuery")
      .with(
        body: hash_including(
          "callback_query_id" => "query123",
          "text" => "Option selected!",
          "show_alert" => false
        )
      )
      .to_return(status: 200, body: {"ok" => true, "result" => true}.to_json)

    result = @client.answer_callback_query("query123", text: "Option selected!")

    assert result["ok"]
  end

  def test_answer_callback_query_with_alert
    stub_request(:post, "https://api.telegram.org/bot123456:ABC-DEF1234ghIkl/answerCallbackQuery")
      .with(
        body: hash_including(
          "callback_query_id" => "query123",
          "text" => "Important!",
          "show_alert" => true
        )
      )
      .to_return(status: 200, body: {"ok" => true, "result" => true}.to_json)

    result = @client.answer_callback_query("query123", text: "Important!", show_alert: true)

    assert result["ok"]
  end

  # ============================================================================
  # EDIT MESSAGE TESTS
  # ============================================================================

  def test_edit_message_text
    stub_request(:post, "https://api.telegram.org/bot123456:ABC-DEF1234ghIkl/editMessageText")
      .with(
        body: hash_including(
          "chat_id" => 12345,
          "message_id" => 99,
          "text" => "Updated text"
        )
      )
      .to_return(status: 200, body: {"ok" => true, "result" => {}}.to_json)

    result = @client.edit_message_text(12345, 99, "Updated text")

    assert result["ok"]
  end

  def test_edit_message_text_with_keyboard
    keyboard = [[{text: "New Button", callback_data: "new"}]]

    stub_request(:post, "https://api.telegram.org/bot123456:ABC-DEF1234ghIkl/editMessageText")
      .with { |request|
        body = JSON.parse(request.body)
        body["chat_id"] == 12345 &&
          body["message_id"] == 99 &&
          body["text"] == "Updated" &&
          body["reply_markup"]["inline_keyboard"].is_a?(Array)
      }
      .to_return(status: 200, body: {"ok" => true, "result" => {}}.to_json)

    result = @client.edit_message_text(12345, 99, "Updated", keyboard: keyboard)

    assert result["ok"]
  end

  # ============================================================================
  # WEBHOOK MANAGEMENT TESTS
  # ============================================================================

  def test_set_webhook
    stub_request(:post, "https://api.telegram.org/bot123456:ABC-DEF1234ghIkl/setWebhook")
      .with { |request|
        body = JSON.parse(request.body)
        body["url"] == "https://example.com/webhook" &&
          body["allowed_updates"] == ["message", "callback_query"]
      }
      .to_return(status: 200, body: {"ok" => true, "result" => true}.to_json)

    result = @client.set_webhook("https://example.com/webhook")

    assert result["ok"]
  end

  def test_set_webhook_with_secret_token
    stub_request(:post, "https://api.telegram.org/bot123456:ABC-DEF1234ghIkl/setWebhook")
      .with { |request|
        body = JSON.parse(request.body)
        body["url"] == "https://example.com/webhook" &&
          body["secret_token"] == "my_secret"
      }
      .to_return(status: 200, body: {"ok" => true, "result" => true}.to_json)

    result = @client.set_webhook("https://example.com/webhook", secret_token: "my_secret")

    assert result["ok"]
  end

  def test_set_webhook_with_custom_allowed_updates
    stub_request(:post, "https://api.telegram.org/bot123456:ABC-DEF1234ghIkl/setWebhook")
      .with { |request|
        body = JSON.parse(request.body)
        body["allowed_updates"] == ["message", "callback_query", "inline_query"]
      }
      .to_return(status: 200, body: {"ok" => true, "result" => true}.to_json)

    result = @client.set_webhook(
      "https://example.com/webhook",
      allowed_updates: ["message", "callback_query", "inline_query"]
    )

    assert result["ok"]
  end

  def test_delete_webhook
    stub_request(:post, "https://api.telegram.org/bot123456:ABC-DEF1234ghIkl/deleteWebhook")
      .to_return(status: 200, body: {"ok" => true, "result" => true}.to_json)

    result = @client.delete_webhook

    assert result["ok"]
  end

  def test_get_webhook_info
    stub_request(:post, "https://api.telegram.org/bot123456:ABC-DEF1234ghIkl/getWebhookInfo")
      .to_return(
        status: 200,
        body: {
          "ok" => true,
          "result" => {
            "url" => "https://example.com/webhook",
            "has_custom_certificate" => false,
            "pending_update_count" => 0
          }
        }.to_json
      )

    result = @client.get_webhook_info

    assert result["ok"]
    assert_equal "https://example.com/webhook", result["result"]["url"]
  end

  # ============================================================================
  # ERROR HANDLING TESTS
  # ============================================================================

  def test_api_error_response
    stub_request(:post, "https://api.telegram.org/bot123456:ABC-DEF1234ghIkl/sendMessage")
      .to_return(
        status: 400,
        body: {
          "ok" => false,
          "error_code" => 400,
          "description" => "Bad Request: chat not found"
        }.to_json
      )

    result = @client.send_text(999999999, "Hello")

    refute result["ok"]
    assert_equal 400, result["error_code"]
    assert_includes result["description"], "chat not found"
  end

  def test_rate_limit_response
    stub_request(:post, "https://api.telegram.org/bot123456:ABC-DEF1234ghIkl/sendMessage")
      .to_return(
        status: 429,
        body: {
          "ok" => false,
          "error_code" => 429,
          "description" => "Too Many Requests: retry after 5",
          "parameters" => {"retry_after" => 5}
        }.to_json
      )

    result = @client.send_text(12345, "Hello")

    refute result["ok"]
    assert_equal 429, result["error_code"]
    assert_equal 5, result["parameters"]["retry_after"]
  end

  def test_network_timeout
    stub_request(:post, "https://api.telegram.org/bot123456:ABC-DEF1234ghIkl/sendMessage")
      .to_timeout

    assert_raises(Net::OpenTimeout) do
      @client.send_text(12345, "Hello")
    end
  end

  def test_api_error_instruments_api_error_event
    stub_request(:post, "https://api.telegram.org/bot123456:ABC-DEF1234ghIkl/sendMessage")
      .to_return(
        status: 401,
        body: {
          "ok" => false,
          "error_code" => 401,
          "description" => "Unauthorized"
        }.to_json
      )

    events = []
    ActiveSupport::Notifications.subscribe("api.error.flow_chat") do |event|
      events << event
    end

    result = @client.send_text(12345, "Hello")

    refute result["ok"]
    assert_equal 1, events.size

    event = events.first
    assert_equal :telegram, event.payload[:platform]
    assert_equal "123456", event.payload[:bot_id]
    assert_equal "sendMessage", event.payload[:api_method]
    assert_equal 401, event.payload[:error_code]
    assert_equal "Unauthorized", event.payload[:error_description]
    assert_equal 12345, event.payload[:chat_id]
  ensure
    ActiveSupport::Notifications.unsubscribe("api.error.flow_chat")
  end

  def test_api_exception_instruments_api_error_event
    stub_request(:post, "https://api.telegram.org/bot123456:ABC-DEF1234ghIkl/sendMessage")
      .to_raise(Errno::ECONNREFUSED)

    events = []
    ActiveSupport::Notifications.subscribe("api.error.flow_chat") do |event|
      events << event
    end

    result = @client.send_text(12345, "Hello")

    refute result["ok"]
    assert_equal 1, events.size

    event = events.first
    assert_equal :telegram, event.payload[:platform]
    assert_equal "123456", event.payload[:bot_id]
    assert_includes event.payload[:message], "Errno::ECONNREFUSED"
  ensure
    ActiveSupport::Notifications.unsubscribe("api.error.flow_chat")
  end

  def test_network_timeout_reraises_without_instrumentation
    stub_request(:post, "https://api.telegram.org/bot123456:ABC-DEF1234ghIkl/sendMessage")
      .to_raise(Net::OpenTimeout.new("execution expired"))

    events = []
    ActiveSupport::Notifications.subscribe("api.error.flow_chat") do |event|
      events << event
    end

    assert_raises(Net::OpenTimeout) do
      @client.send_text(12345, "Hello")
    end

    # Network timeouts are re-raised for retry logic - no api.error instrumentation
    assert_equal 0, events.size
  ensure
    ActiveSupport::Notifications.unsubscribe("api.error.flow_chat")
  end

  # ============================================================================
  # GET BOT INFO TEST
  # ============================================================================

  def test_get_me
    stub_request(:post, "https://api.telegram.org/bot123456:ABC-DEF1234ghIkl/getMe")
      .to_return(
        status: 200,
        body: {
          "ok" => true,
          "result" => {
            "id" => 123456,
            "is_bot" => true,
            "first_name" => "TestBot",
            "username" => "test_bot",
            "can_join_groups" => true,
            "can_read_all_group_messages" => false,
            "supports_inline_queries" => false
          }
        }.to_json
      )

    result = @client.get_me

    assert result["ok"]
    assert_equal "TestBot", result["result"]["first_name"]
    assert result["result"]["is_bot"]
  end

  # ============================================================================
  # DELETE MESSAGE TEST
  # ============================================================================

  def test_delete_message
    stub_request(:post, "https://api.telegram.org/bot123456:ABC-DEF1234ghIkl/deleteMessage")
      .with(
        body: hash_including(
          "chat_id" => 12345,
          "message_id" => 99
        )
      )
      .to_return(status: 200, body: {"ok" => true, "result" => true}.to_json)

    result = @client.delete_message(12345, 99)

    assert result["ok"]
  end

  # ============================================================================
  # SEND CHAT ACTION TESTS
  # ============================================================================

  def test_send_chat_action_defaults_to_typing
    stub_request(:post, "https://api.telegram.org/bot123456:ABC-DEF1234ghIkl/sendChatAction")
      .with(
        body: hash_including(
          "chat_id" => 12345,
          "action" => "typing"
        )
      )
      .to_return(status: 200, body: {"ok" => true, "result" => true}.to_json)

    result = @client.send_chat_action(12345)

    assert result["ok"]
  end

  def test_send_chat_action_passes_through_custom_action
    stub_request(:post, "https://api.telegram.org/bot123456:ABC-DEF1234ghIkl/sendChatAction")
      .with(
        body: hash_including(
          "chat_id" => 12345,
          "action" => "upload_photo"
        )
      )
      .to_return(status: 200, body: {"ok" => true, "result" => true}.to_json)

    result = @client.send_chat_action(12345, action: "upload_photo")

    assert result["ok"]
  end

  def test_indicate_typing_sends_typing_action
    stub_request(:post, "https://api.telegram.org/bot123456:ABC-DEF1234ghIkl/sendChatAction")
      .with(
        body: hash_including(
          "chat_id" => 12345,
          "action" => "typing"
        )
      )
      .to_return(status: 200, body: {"ok" => true, "result" => true}.to_json)

    result = @client.indicate_typing(12345)

    assert result["ok"]
  end
end

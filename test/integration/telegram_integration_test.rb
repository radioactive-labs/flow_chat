require "test_helper"
require "webmock/minitest"

class TelegramIntegrationTest < Minitest::Test
  class GreetingFlow < FlowChat::Flow
    def main_page
      name = app.screen(:name) { |p| p.ask "What is your name?" }
      app.say "Hello, #{name}!"
    end
  end

  class ChoiceFlow < FlowChat::Flow
    def main_page
      choice = app.screen(:choice) do |p|
        p.select "Pick a color:", {"red" => "Red", "green" => "Green", "blue" => "Blue"}
      end
      app.say "You picked #{choice}!"
    end
  end

  class MediaFlow < FlowChat::Flow
    def main_page
      app.say "Here's an image", media: {type: :photo, url: "https://example.com/photo.jpg"}
    end
  end

  def setup
    @config = FlowChat::Telegram::Configuration.new("test")
    @config.bot_token = "123456:ABC-DEF"
    @config.secret_token = "test_secret"

    WebMock.enable!
    WebMock.reset!

    # Stub all Telegram API calls
    stub_request(:post, /api\.telegram\.org/).to_return(
      status: 200,
      body: {"ok" => true, "result" => {"message_id" => 123}}.to_json
    )
  end

  def teardown
    WebMock.disable!
    WebMock.reset!
  end

  # ============================================================================
  # FULL FLOW INTEGRATION TESTS
  # ============================================================================

  def test_full_greeting_flow_prompts_for_name
    controller = create_telegram_controller(
      message: build_message(text: "/start")
    )

    run_processor(controller, GreetingFlow)

    # Should send "What is your name?" prompt
    assert_requested :post, "https://api.telegram.org/bot123456:ABC-DEF/sendMessage" do |req|
      body = JSON.parse(req.body)
      body["text"] == "What is your name?" && body["chat_id"].to_s == "123"
    end
  end

  def test_full_greeting_flow_completes_with_name
    # Set up session with name already collected
    session_data = {"name" => "Alice"}

    controller = create_telegram_controller(
      message: build_message(text: "ignored")  # Input is ignored since name is in session
    )

    run_processor(controller, GreetingFlow, session_data: session_data)

    # Should send greeting
    assert_requested :post, "https://api.telegram.org/bot123456:ABC-DEF/sendMessage" do |req|
      body = JSON.parse(req.body)
      body["text"] == "Hello, Alice!" && body["chat_id"].to_s == "123"
    end
  end

  def test_choice_flow_shows_inline_keyboard
    controller = create_telegram_controller(
      message: build_message(text: "start")
    )

    run_processor(controller, ChoiceFlow)

    # Should send message with inline keyboard
    assert_requested :post, "https://api.telegram.org/bot123456:ABC-DEF/sendMessage" do |req|
      body = JSON.parse(req.body)
      body["text"] == "Pick a color:" &&
        body["reply_markup"] &&
        body["reply_markup"]["inline_keyboard"].is_a?(Array)
    end
  end

  def test_choice_flow_callback_completes_flow
    # Set up session with:
    # - $start$ to indicate flow has been initialized (first input consumed)
    # - telegram_choices to have valid choice options
    session_data = {
      "$start$" => "start",
      "telegram_choices" => {"red" => "Red", "green" => "Green", "blue" => "Blue"}
    }

    controller = create_telegram_controller(
      callback_query: build_callback_query(data: "green")
    )

    run_processor(controller, ChoiceFlow, session_data: session_data)

    # Should answer callback query
    assert_requested :post, "https://api.telegram.org/bot123456:ABC-DEF/answerCallbackQuery"

    # Should send completion message
    assert_requested :post, "https://api.telegram.org/bot123456:ABC-DEF/sendMessage" do |req|
      body = JSON.parse(req.body)
      body["text"] == "You picked green!"
    end
  end

  def test_media_flow_sends_photo
    controller = create_telegram_controller(
      message: build_message(text: "show")
    )

    run_processor(controller, MediaFlow)

    # Should send photo
    assert_requested :post, "https://api.telegram.org/bot123456:ABC-DEF/sendPhoto" do |req|
      body = JSON.parse(req.body)
      body["photo"] == "https://example.com/photo.jpg" &&
        body["caption"] == "Here's an image"
    end
  end

  # ============================================================================
  # WEBHOOK SIGNATURE VALIDATION TESTS
  # ============================================================================

  def test_webhook_rejects_invalid_signature
    controller = create_telegram_controller(
      message: build_message(text: "hello"),
      secret_token: "wrong_secret"
    )

    run_processor(controller, GreetingFlow)

    assert_equal :ok, controller.last_head_status
    # Should NOT send any message
    assert_not_requested :post, "https://api.telegram.org/bot123456:ABC-DEF/sendMessage"
  end

  def test_webhook_accepts_valid_signature
    controller = create_telegram_controller(
      message: build_message(text: "hello"),
      secret_token: "test_secret"
    )

    run_processor(controller, GreetingFlow)

    # Should send message (signature valid)
    assert_requested :post, "https://api.telegram.org/bot123456:ABC-DEF/sendMessage"
  end

  def test_webhook_accepts_missing_signature_when_no_secret_configured
    config = FlowChat::Telegram::Configuration.new("no_secret")
    config.bot_token = "123456:ABC-DEF"
    config.secret_token = nil

    controller = create_telegram_controller(
      message: build_message(text: "hello"),
      secret_token: nil
    )

    run_processor(controller, GreetingFlow, config: config)

    # Should process successfully
    assert_requested :post, "https://api.telegram.org/bot123456:ABC-DEF/sendMessage"
  end

  # ============================================================================
  # CONTEXT EXTRACTION TESTS
  # ============================================================================

  def test_context_extracts_user_info_from_message
    controller = create_telegram_controller(
      message: {
        "message_id" => 42,
        "text" => "test",
        "chat" => {"id" => 123, "type" => "group"},
        "from" => {"id" => 456, "first_name" => "John", "last_name" => "Doe", "username" => "johndoe"},
        "date" => 1700000000
      }
    )

    captured_context = nil
    run_processor(controller, GreetingFlow) do |context|
      captured_context = context.dup
    end

    assert_equal "123", captured_context["request.id"]
    assert_equal "456", captured_context["request.user_id"]
    assert_equal "John Doe", captured_context["request.user_name"]
    assert_equal "johndoe", captured_context["request.username"]
    assert_equal :telegram, captured_context["request.platform"]
    assert_equal :telegram_bot_api, captured_context["request.gateway"]
    assert_equal "group", captured_context["telegram.chat_type"]
  end

  def test_context_extracts_location_message
    controller = create_telegram_controller(
      message: {
        "message_id" => 1,
        "location" => {"latitude" => 51.5074, "longitude" => -0.1278},
        "chat" => {"id" => 123, "type" => "private"},
        "from" => {"id" => 456, "first_name" => "John"},
        "date" => Time.now.to_i
      }
    )

    captured_context = nil
    run_processor(controller, GreetingFlow) do |context|
      captured_context = context.dup
    end

    assert_equal "$location$", captured_context.input
    assert_equal({"latitude" => 51.5074, "longitude" => -0.1278}, captured_context["request.location"])
  end

  def test_context_extracts_photo_message
    controller = create_telegram_controller(
      message: {
        "message_id" => 1,
        "photo" => [
          {"file_id" => "small", "file_unique_id" => "small_unique", "width" => 90, "height" => 90},
          {"file_id" => "large", "file_unique_id" => "large_unique", "width" => 800, "height" => 600}
        ],
        "chat" => {"id" => 123, "type" => "private"},
        "from" => {"id" => 456, "first_name" => "John"},
        "date" => Time.now.to_i
      }
    )

    captured_context = nil
    run_processor(controller, GreetingFlow) do |context|
      captured_context = context.dup
    end

    assert_equal "$media$", captured_context.input
    assert_equal :photo, captured_context["request.media"][:type]
    assert_equal "large", captured_context["request.media"][:file_id]
  end

  # ============================================================================
  # CHOICE MAPPER INTEGRATION TESTS
  # ============================================================================

  def test_choice_mapper_stores_choices_in_session
    session_data = {}

    controller = create_telegram_controller(
      message: build_message(text: "start")
    )

    run_processor(controller, ChoiceFlow, session_data: session_data)

    # Choice mapper should store choices with key "telegram_choices"
    assert session_data.key?("telegram_choices")
    assert_equal({"red" => "Red", "green" => "Green", "blue" => "Blue"}, session_data["telegram_choices"])
  end

  def test_choice_mapper_passes_through_valid_callback_data
    # Callback data "green" should pass through to the flow
    # Include $start$ to indicate conversation has started
    session_data = {
      "$start$" => "start",
      "telegram_choices" => {"red" => "Red", "green" => "Green", "blue" => "Blue"}
    }

    controller = create_telegram_controller(
      callback_query: build_callback_query(data: "green")
    )

    run_processor(controller, ChoiceFlow, session_data: session_data)

    # Should complete flow with selected choice
    assert_requested :post, "https://api.telegram.org/bot123456:ABC-DEF/sendMessage" do |req|
      body = JSON.parse(req.body)
      body["text"] == "You picked green!"
    end
  end

  private

  def build_message(text: nil, chat_id: 123, user_id: 456, first_name: "John")
    {
      "message_id" => rand(1000),
      "text" => text,
      "chat" => {"id" => chat_id, "type" => "private"},
      "from" => {"id" => user_id, "first_name" => first_name},
      "date" => Time.now.to_i
    }
  end

  def build_callback_query(data:, chat_id: 123, user_id: 456)
    {
      "id" => "query_#{rand(1000)}",
      "data" => data,
      "from" => {"id" => user_id, "first_name" => "John"},
      "message" => {"message_id" => 10, "chat" => {"id" => chat_id, "type" => "private"}}
    }
  end

  def create_telegram_controller(message: nil, callback_query: nil, secret_token: "test_secret")
    body = {}
    body["message"] = message if message
    body["callback_query"] = callback_query if callback_query

    controller = Object.new
    request = Object.new
    body_io = StringIO.new(body.to_json)

    request.define_singleton_method(:post?) { true }
    request.define_singleton_method(:body) { body_io }
    request.define_singleton_method(:headers) do
      h = {}
      h["X-Telegram-Bot-Api-Secret-Token"] = secret_token if secret_token
      h
    end

    controller.define_singleton_method(:request) { request }
    controller.define_singleton_method(:head) { |status| @last_head_status = status }
    controller.define_singleton_method(:last_head_status) { @last_head_status }

    controller
  end

  def create_session_store(data)
    Class.new do
      define_method(:initialize) { |_context| @data = data }
      define_method(:get) { |key| @data[key.to_s] }
      define_method(:set) { |key, value| @data[key.to_s] = value }
      define_method(:delete) { |key| @data.delete(key.to_s) }
      define_method(:clear) { @data.clear }
      define_method(:destroy) { @data.clear }
    end
  end

  def run_processor(controller, flow_class, session_data: {}, config: nil, &context_callback)
    config ||= @config
    session_store = create_session_store(session_data)

    processor = FlowChat::Processor.new(controller) do |c|
      c.use_gateway FlowChat::Telegram::Gateway::BotApi, config
      c.use_session_store session_store

      if context_callback
        c.use_middleware Class.new {
          define_method(:initialize) { |app|
            @app = app
            @callback = context_callback
          }
          define_method(:call) { |context|
            @callback.call(context)
            @app.call(context)
          }
        }
      end
    end

    processor.run(flow_class, :main_page)
  end
end

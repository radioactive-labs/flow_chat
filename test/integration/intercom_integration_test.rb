# frozen_string_literal: true

# Module: IntercomIntegrationTest
#
# Purpose:
# Integration tests for the Intercom API gateway, testing full flow execution
# with the Intercom platform for customer support automation.
#
# Coverage:
# - Full flow integration with prompts and completion
# - Multi-step flows collecting multiple user inputs
# - Choice flows (Intercom uses numbered text choices)
# - Webhook signature validation (X-Hub-Signature with SHA1)
# - Context extraction (user info, conversation details)
# - HTML to Markdown conversion for message content
# - $start$ session flag handling for non-USSD platforms
# - Event type filtering (user.created, user.replied)
#
# Architecture:
# The Intercom gateway processes webhook notifications from Intercom and sends
# replies via the Intercom REST API. Unlike USSD, Intercom is asynchronous:
# - Webhook receives conversation events (user.created, user.replied)
# - Gateway extracts message content and user context
# - Flow processes input and generates response
# - Response sent back via Intercom API
#
# Key Test Patterns:
# - WebMock stubs Intercom API calls to verify request content
# - Session data hash passed to processor to simulate state
# - Controller mock simulates Rails controller interface
# - Signature validation uses HMAC-SHA1 with client_secret
#
# Session Behavior:
# - $start$ flag consumed on first interaction (non-USSD platform)
# - Session destroyed after flow completion (terminal state)
# - Session persists between screens until flow ends
#
# Special Considerations:
# - Intercom messages are HTML; gateway converts to Markdown for flows
# - Choices rendered as numbered text lists (no interactive buttons)
# - HEAD requests used for webhook URL validation
# - Signature validation can be disabled for development

require "test_helper"
require "webmock/minitest"

class IntercomIntegrationTest < Minitest::Test
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

  class MultiStepFlow < FlowChat::Flow
    def main_page
      name = app.screen(:name) { |p| p.ask "What is your name?" }
      email = app.screen(:email) { |p| p.ask "What is your email?" }
      app.say "Thanks #{name}, we'll contact you at #{email}!"
    end
  end

  def setup
    @config = FlowChat::Intercom::Configuration.new("test_integration")
    @config.access_token = "test_access_token"
    @config.client_secret = "test_client_secret"
    @config.admin_id = "admin_123"

    WebMock.enable!
    WebMock.reset!

    # Stub all Intercom API calls
    stub_request(:post, /api\.intercom\.io\/conversations\/.*\/reply/).to_return(
      status: 200,
      body: {"type" => "conversation", "id" => "conv_123", "conversation_message" => {"id" => "msg_123"}}.to_json,
      headers: {"Content-Type" => "application/json"}
    )
  end

  def teardown
    WebMock.disable!
    WebMock.reset!
    FlowChat::Intercom::Configuration.clear_all!
  end

  # ============================================================================
  # FULL FLOW INTEGRATION TESTS
  # ============================================================================

  def test_full_greeting_flow_prompts_for_name
    controller = create_intercom_controller(
      webhook: build_conversation_created_webhook(message: "Hi")
    )

    run_processor(controller, GreetingFlow)

    # Should send "What is your name?" prompt via Intercom API
    assert_requested :post, "https://api.intercom.io/conversations/conv_123/reply" do |req|
      body = JSON.parse(req.body)
      body["body"].include?("What is your name?")
    end
  end

  def test_full_greeting_flow_completes_with_name
    # Set up session with name already collected
    session_data = {"name" => "Alice", "$start$" => "hi"}

    controller = create_intercom_controller(
      webhook: build_conversation_reply_webhook(message: "ignored")
    )

    run_processor(controller, GreetingFlow, session_data: session_data)

    # Should send greeting
    assert_requested :post, "https://api.intercom.io/conversations/conv_123/reply" do |req|
      body = JSON.parse(req.body)
      body["body"].include?("Hello, Alice!")
    end
  end

  def test_multi_step_flow_collects_multiple_inputs
    # Step 1: Initial message - should prompt for name
    controller1 = create_intercom_controller(
      webhook: build_conversation_created_webhook(message: "Hello")
    )

    session_data = {}
    run_processor(controller1, MultiStepFlow, session_data: session_data)

    assert_requested :post, "https://api.intercom.io/conversations/conv_123/reply" do |req|
      body = JSON.parse(req.body)
      body["body"].include?("What is your name?")
    end

    # Step 2: User provides name - should prompt for email
    WebMock.reset!
    stub_request(:post, /api\.intercom\.io\/conversations\/.*\/reply/).to_return(
      status: 200,
      body: {"type" => "conversation", "id" => "conv_123"}.to_json,
      headers: {"Content-Type" => "application/json"}
    )

    controller2 = create_intercom_controller(
      webhook: build_conversation_reply_webhook(message: "John")
    )

    run_processor(controller2, MultiStepFlow, session_data: session_data)

    assert_requested :post, "https://api.intercom.io/conversations/conv_123/reply" do |req|
      body = JSON.parse(req.body)
      body["body"].include?("What is your email?")
    end

    # Step 3: User provides email - should complete flow
    WebMock.reset!
    stub_request(:post, /api\.intercom\.io\/conversations\/.*\/reply/).to_return(
      status: 200,
      body: {"type" => "conversation", "id" => "conv_123"}.to_json,
      headers: {"Content-Type" => "application/json"}
    )

    controller3 = create_intercom_controller(
      webhook: build_conversation_reply_webhook(message: "john@example.com")
    )

    run_processor(controller3, MultiStepFlow, session_data: session_data)

    assert_requested :post, "https://api.intercom.io/conversations/conv_123/reply" do |req|
      body = JSON.parse(req.body)
      body["body"].include?("Thanks John") && body["body"].include?("john@example.com")
    end
  end

  # ============================================================================
  # CHOICE FLOW TESTS (Intercom uses numbered text choices)
  # ============================================================================

  def test_choice_flow_shows_numbered_choices
    controller = create_intercom_controller(
      webhook: build_conversation_created_webhook(message: "start")
    )

    run_processor(controller, ChoiceFlow)

    # Should send message with numbered choices
    assert_requested :post, "https://api.intercom.io/conversations/conv_123/reply" do |req|
      body = JSON.parse(req.body)
      message = body["body"]
      # Intercom renderer formats choices as numbered list
      message.include?("Pick a color:") &&
        message.include?("1.") && message.include?("Red") &&
        message.include?("2.") && message.include?("Green") &&
        message.include?("3.") && message.include?("Blue") &&
        message.include?("Reply with the number of your choice")
    end
  end

  def test_choice_flow_accepts_numeric_input
    # For Intercom, there's no built-in choice mapper like USSD
    # The flow would need to handle numeric input directly
    # This test shows the expected behavior when user enters "2" for "Green"
    session_data = {
      "$start$" => "start",
      "choice" => "green"  # Assuming the flow maps "2" -> "green"
    }

    controller = create_intercom_controller(
      webhook: build_conversation_reply_webhook(message: "2")
    )

    # Note: The actual choice mapping would need to be done in the flow logic
    # since Intercom doesn't have a ChoiceMapper middleware
    run_processor(controller, ChoiceFlow, session_data: session_data)

    # Should send completion message
    assert_requested :post, "https://api.intercom.io/conversations/conv_123/reply" do |req|
      body = JSON.parse(req.body)
      body["body"].include?("You picked green!")
    end
  end

  # ============================================================================
  # WEBHOOK SIGNATURE VALIDATION TESTS
  # ============================================================================

  def test_webhook_rejects_invalid_signature
    controller = create_intercom_controller(
      webhook: build_conversation_created_webhook(message: "hello"),
      signature: "sha1=invalid_signature"
    )

    run_processor(controller, GreetingFlow)

    assert_equal :ok, controller.last_head_status
    # Should NOT send any message
    assert_not_requested :post, "https://api.intercom.io/conversations/conv_123/reply"
  end

  def test_webhook_accepts_valid_signature
    webhook_body = build_conversation_created_webhook(message: "hello")
    valid_signature = generate_webhook_signature(webhook_body.to_json)

    controller = create_intercom_controller(
      webhook: webhook_body,
      signature: "sha1=#{valid_signature}"
    )

    run_processor(controller, GreetingFlow)

    # Should send message (signature valid)
    assert_requested :post, "https://api.intercom.io/conversations/conv_123/reply"
  end

  def test_webhook_rejects_missing_signature
    controller = create_intercom_controller(
      webhook: build_conversation_created_webhook(message: "hello"),
      signature: nil
    )

    run_processor(controller, GreetingFlow)

    assert_equal :ok, controller.last_head_status
    assert_not_requested :post, "https://api.intercom.io/conversations/conv_123/reply"
  end

  def test_webhook_accepts_any_signature_when_validation_disabled
    @config.skip_signature_validation = true

    controller = create_intercom_controller(
      webhook: build_conversation_created_webhook(message: "hello"),
      signature: "sha1=completely_invalid"
    )

    run_processor(controller, GreetingFlow)

    # Should process successfully despite invalid signature
    assert_requested :post, "https://api.intercom.io/conversations/conv_123/reply"
  end

  def test_webhook_url_validation_head_request
    # Intercom sends HEAD request to validate webhook URL
    controller = create_intercom_controller_for_head_request

    run_processor(controller, GreetingFlow)

    assert_equal :ok, controller.last_head_status
    # Should NOT send any message for HEAD requests
    assert_not_requested :post, "https://api.intercom.io/conversations/conv_123/reply"
  end

  # ============================================================================
  # CONTEXT EXTRACTION TESTS
  # ============================================================================

  def test_context_extracts_user_info_from_conversation
    webhook = build_conversation_created_webhook(
      message: "test",
      conversation_id: "conv_456",
      user_id: "user_789",
      user_name: "Jane Smith",
      user_email: "jane@example.com",
      user_phone: "+1234567890"
    )

    controller = create_intercom_controller(webhook: webhook)

    captured_context = nil
    run_processor(controller, GreetingFlow) do |context|
      captured_context = context.dup
    end

    assert_equal "conv_456", captured_context["request.id"]
    assert_equal "user_789", captured_context["request.user_id"]
    assert_equal "Jane Smith", captured_context["request.user_name"]
    assert_equal "jane@example.com", captured_context["request.email"]
    assert_equal "+1234567890", captured_context["request.msisdn"]
    assert_equal :intercom, captured_context["request.platform"]
    assert_equal :intercom_api, captured_context["request.gateway"]
  end

  def test_context_extracts_conversation_topic
    webhook = build_conversation_created_webhook(message: "test")

    controller = create_intercom_controller(webhook: webhook)

    captured_context = nil
    run_processor(controller, GreetingFlow) do |context|
      captured_context = context.dup
    end

    assert_equal "conversation.user.created", captured_context["intercom.topic"]
  end

  def test_context_extracts_reply_topic
    webhook = build_conversation_reply_webhook(message: "reply message")

    # Need to set $start$ for non-USSD platforms on subsequent messages
    session_data = {"$start$" => "initial"}

    controller = create_intercom_controller(webhook: webhook)

    captured_context = nil
    run_processor(controller, GreetingFlow, session_data: session_data) do |context|
      captured_context = context.dup
    end

    assert_equal "conversation.user.replied", captured_context["intercom.topic"]
  end

  def test_context_includes_intercom_client
    webhook = build_conversation_created_webhook(message: "test")

    controller = create_intercom_controller(webhook: webhook)

    captured_context = nil
    run_processor(controller, GreetingFlow) do |context|
      captured_context = context.dup
    end

    assert_instance_of FlowChat::Intercom::Client, captured_context["intercom.client"]
  end

  def test_context_stores_raw_webhook_body
    webhook = build_conversation_created_webhook(message: "test")

    controller = create_intercom_controller(webhook: webhook)

    captured_context = nil
    run_processor(controller, GreetingFlow) do |context|
      captured_context = context.dup
    end

    assert_kind_of Hash, captured_context["request.body"]
    assert_equal "conversation.user.created", captured_context["request.body"]["topic"]
  end

  # ============================================================================
  # HTML TO MARKDOWN CONVERSION TESTS
  # ============================================================================

  def test_html_message_converted_to_markdown
    webhook = build_conversation_created_webhook(
      message: "<p>Hello, I need help with <strong>my account</strong>.</p>"
    )

    controller = create_intercom_controller(webhook: webhook)

    captured_context = nil
    run_processor(controller, GreetingFlow) do |context|
      captured_context = context.dup
    end

    # HTML should be converted to markdown
    assert_equal "Hello, I need help with **my account**.", captured_context.input
  end

  def test_html_message_with_link_converted_to_markdown
    webhook = build_conversation_created_webhook(
      message: '<p>Check out <a href="https://example.com">this link</a> please</p>'
    )

    controller = create_intercom_controller(webhook: webhook)

    captured_context = nil
    run_processor(controller, GreetingFlow) do |context|
      captured_context = context.dup
    end

    assert_equal "Check out [this link](https://example.com) please", captured_context.input
  end

  # ============================================================================
  # START FLAG HANDLING TESTS (non-USSD platforms)
  # ============================================================================

  def test_start_flag_consumes_first_input
    # For non-USSD platforms, the first input is consumed to set $start$
    controller = create_intercom_controller(
      webhook: build_conversation_created_webhook(message: "Hello!")
    )

    session_data = {}
    run_processor(controller, GreetingFlow, session_data: session_data)

    # $start$ should be set in session
    assert session_data.key?("$start$")

    # Flow should prompt for name (first input consumed)
    assert_requested :post, "https://api.intercom.io/conversations/conv_123/reply" do |req|
      body = JSON.parse(req.body)
      body["body"].include?("What is your name?")
    end
  end

  def test_subsequent_input_used_after_start_flag_set
    # When $start$ is already set, input should be used normally
    session_data = {"$start$" => "initial"}

    controller = create_intercom_controller(
      webhook: build_conversation_reply_webhook(message: "Alice")
    )

    run_processor(controller, GreetingFlow, session_data: session_data)

    # Flow should complete with greeting (session is destroyed after completion)
    assert_requested :post, "https://api.intercom.io/conversations/conv_123/reply" do |req|
      body = JSON.parse(req.body)
      body["body"].include?("Hello, Alice!")
    end
  end

  # ============================================================================
  # EVENT TYPE FILTERING TESTS
  # ============================================================================

  def test_ignores_admin_events_by_default
    webhook = {
      "topic" => "conversation.admin.replied",
      "data" => {
        "item" => {
          "type" => "conversation",
          "id" => "conv_123"
        }
      }
    }

    controller = create_intercom_controller(webhook: webhook)

    run_processor(controller, GreetingFlow)

    # Should return OK but not process the message
    assert_equal :ok, controller.last_head_status
    assert_not_requested :post, "https://api.intercom.io/conversations/conv_123/reply"
  end

  def test_processes_user_created_events
    webhook = build_conversation_created_webhook(message: "Hi there")

    controller = create_intercom_controller(webhook: webhook)

    run_processor(controller, GreetingFlow)

    # Should process and send response
    assert_requested :post, "https://api.intercom.io/conversations/conv_123/reply"
  end

  def test_processes_user_replied_events
    webhook = build_conversation_reply_webhook(message: "Follow up")
    session_data = {"$start$" => "initial"}

    controller = create_intercom_controller(webhook: webhook)

    run_processor(controller, GreetingFlow, session_data: session_data)

    # Should process and send response
    assert_requested :post, "https://api.intercom.io/conversations/conv_123/reply"
  end

  private

  def build_conversation_created_webhook(
    message:,
    conversation_id: "conv_123",
    user_id: "user_456",
    user_name: "John Doe",
    user_email: "user@example.com",
    user_phone: nil
  )
    contact = {
      "type" => "contact",
      "id" => user_id,
      "external_id" => "external_123"
    }
    contact["name"] = user_name if user_name
    contact["email"] = user_email if user_email
    contact["phone"] = user_phone if user_phone

    {
      "topic" => "conversation.user.created",
      "data" => {
        "item" => {
          "type" => "conversation",
          "id" => conversation_id,
          "source" => {
            "type" => "conversation",
            "id" => "source_123",
            "delivered_as" => "customer_initiated",
            "subject" => "",
            "body" => message,
            "author" => {
              "type" => "lead",
              "id" => user_id,
              "name" => user_name,
              "email" => user_email
            },
            "attachments" => [],
            "url" => "http://example.com/",
            "redacted" => false
          },
          "contacts" => {
            "type" => "contact.list",
            "contacts" => [contact]
          }
        }
      }
    }
  end

  def build_conversation_reply_webhook(
    message:,
    conversation_id: "conv_123",
    user_id: "user_456"
  )
    {
      "topic" => "conversation.user.replied",
      "data" => {
        "item" => {
          "type" => "conversation",
          "id" => conversation_id,
          "source" => {
            "type" => "conversation",
            "id" => "source_123",
            "delivered_as" => "customer_initiated",
            "subject" => "",
            "body" => "Initial message",
            "author" => {
              "type" => "lead",
              "id" => user_id,
              "name" => "John Doe",
              "email" => "user@example.com"
            },
            "attachments" => [],
            "url" => "http://example.com/",
            "redacted" => false
          },
          "contacts" => {
            "type" => "contact.list",
            "contacts" => [
              {
                "type" => "contact",
                "id" => user_id,
                "external_id" => "external_123"
              }
            ]
          },
          "conversation_parts" => {
            "conversation_parts" => [
              {
                "id" => "part_1",
                "part_type" => "comment",
                "body" => message,
                "author" => {"type" => "user"}
              }
            ]
          }
        }
      }
    }
  end

  def generate_webhook_signature(body)
    OpenSSL::HMAC.hexdigest(
      OpenSSL::Digest.new("sha1"),
      @config.client_secret,
      body
    )
  end

  def create_intercom_controller(webhook:, signature: :auto)
    body = webhook.to_json

    if signature == :auto
      calculated_signature = generate_webhook_signature(body)
      signature = "sha1=#{calculated_signature}"
    end

    controller = Object.new
    request = Object.new
    body_io = StringIO.new(body)

    request.define_singleton_method(:post?) { true }
    request.define_singleton_method(:head?) { false }
    request.define_singleton_method(:body) { body_io }
    request.define_singleton_method(:path) { "/intercom/webhook" }
    request.define_singleton_method(:request_method) { "POST" }
    request.define_singleton_method(:cookies) { {} }
    request.define_singleton_method(:headers) do
      h = {}
      h["X-Hub-Signature"] = signature if signature
      h
    end

    controller.define_singleton_method(:request) { request }
    controller.define_singleton_method(:head) { |status| @last_head_status = status }
    controller.define_singleton_method(:last_head_status) { @last_head_status }
    controller.define_singleton_method(:render) { |options| @render_options = options }
    controller.define_singleton_method(:render_options) { @render_options }

    controller
  end

  def create_intercom_controller_for_head_request
    controller = Object.new
    request = Object.new

    request.define_singleton_method(:post?) { false }
    request.define_singleton_method(:head?) { true }
    request.define_singleton_method(:path) { "/intercom/webhook" }
    request.define_singleton_method(:request_method) { "HEAD" }

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
      c.use_gateway FlowChat::Intercom::Gateway::IntercomApi, config
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

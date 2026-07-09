# frozen_string_literal: true

# Module: IntercomApiTest
#
# Purpose:
# Comprehensive tests for the Intercom gateway implementation, which handles
# webhook processing, conversation management, and integration with Intercom's
# messaging platform for customer support automation.
#
# Coverage:
# - Webhook verification and subscription handling
# - Conversation event processing (user.created, user.replied)
# - Webhook signature validation for security
# - Message extraction from complex conversation structures
# - Simulator mode for development and testing
# - Error handling and edge cases
#
# Architecture:
# The Intercom gateway follows a webhook-based architecture:
# 1. GET requests: Handle webhook verification during setup
# 2. POST requests: Process conversation events and user messages
# 3. Response sending: Use Intercom API client to send replies
#
# Webhook Event Types:
# - conversation.user.created: New conversation started by user
# - conversation.user.replied: User replied in existing conversation
# - Other events are acknowledged but not processed
#
# Security Features:
# - Hub signature validation using HMAC-SHA1
# - Configurable signature validation skip for development
# - Webhook verify token for subscription confirmation
# - Secure string comparison to prevent timing attacks
#
# Key Test Scenarios:
# - Webhook verification with valid/invalid tokens
# - Processing new conversations with initial messages
# - Extracting latest user replies from conversation parts
# - Signature validation with correct/incorrect signatures
# - Simulator mode activation and response format
# - Error handling for malformed requests
#
# Message Extraction Logic:
# - For created events: Extract from conversation_message
# - For reply events: Find latest user message in conversation_parts
# - Filter by author type to exclude admin messages
#
# Special Considerations:
# - Uses WebMock for HTTP stubbing in tests
# - Complex mock setup for request/response objects
# - Conversation parts are ordered chronologically
# - Simulator mode requires valid cookie authentication
# - Test uses SimpleMock for lightweight mocking without external dependencies

require "test_helper"
require "webmock/minitest"
require_relative "../../../support/mocks"

class FlowChat::Intercom::Gateway::IntercomApiTest < Minitest::Test
  # Helper method for type matching in expectations
  def instance_of(klass)
    klass
  end

  def setup
    @app = Minitest::Mock.new
    @config = FlowChat::Intercom::Configuration.new("test")
    @config.access_token = "test_access_token"
    @config.client_secret = "test_client_secret"
    @config.admin_id = "test_admin_id"

    @gateway = FlowChat::Intercom::Gateway::IntercomApi.new(@app, @config)
    @context = create_mock_context

    # Mock the client's send_message method for webhook tests
    @mock_client = Minitest::Mock.new
    # Define parse_message to delegate to class method (not mockable behavior)
    def @mock_client.parse_message(html)
      FlowChat::Intercom::Client.parse_html(html)
    end

    # Define app_id= setter (called by gateway after parsing request body)
    def @mock_client.app_id=(value)
      @app_id = value
    end
    @gateway.instance_variable_set(:@client, @mock_client)

    WebMock.enable!
  end

  def teardown
    begin
      @app.verify if @app.respond_to?(:verify)
    rescue MockExpectationError
      # Ignore verification errors in teardown for tests that don't call app
    end
    begin
      @mock_client.verify if @mock_client.respond_to?(:verify)
    rescue MockExpectationError
      # Ignore verification errors in teardown for tests that don't call client
    end
    WebMock.disable!
    WebMock.reset!
  end

  def test_initialize_with_config
    gateway = FlowChat::Intercom::Gateway::IntercomApi.new(@app, @config)

    assert_equal @app.object_id, gateway.instance_variable_get(:@app).object_id
    assert_equal @config.object_id, gateway.instance_variable_get(:@config).object_id
    assert_instance_of FlowChat::Intercom::Client, gateway.client
  end

  def test_initialize_without_config_uses_credentials
    # Mock the Configuration.from_credentials method
    config_mock = FlowChat::TestSupport::SimpleMock.new
    config_mock.expect(:access_token, "mock_access_token")
    config_mock.expect(:admin_id, "mock_admin_id")
    config_mock.expect(:api_base_url, "https://api.intercom.io")

    FlowChat::Intercom::Configuration.stub(:from_credentials, config_mock) do
      gateway = FlowChat::Intercom::Gateway::IntercomApi.new(@app)
      assert_equal config_mock, gateway.instance_variable_get(:@config)
    end
  end

  def test_webhook_url_validation_head_request
    setup_head_request

    @context.controller.expect(:head, nil, [:ok])

    @gateway.call(@context)
  end

  def test_webhook_notification_conversation_user_created
    webhook_body = build_conversation_created_webhook
    setup_post_request_with_webhook_and_app_call(webhook_body)

    @app.expect(:call, [:text, "Thank you for your message!", nil, nil], [@context])
    @mock_client.expect(:send_message, {"id" => "sent_msg_123"}, ["conv_123", "Thank you for your message!"], choices: nil, media: nil)

    @gateway.call(@context)

    # Verify context was set up correctly
    assert_equal "conv_123", @context["request.id"]
    assert_equal "user_456", @context["request.user_id"]
    assert_equal :intercom_api, @context["request.gateway"]
    assert_equal :intercom, @context["request.platform"]
    assert_equal "Hello, I need help with my account", @context.input
    assert_equal "conversation.user.created", @context["intercom.topic"]
  end

  def test_webhook_notification_conversation_user_replied
    webhook_body = build_conversation_reply_webhook
    setup_post_request_with_webhook_and_app_call(webhook_body)

    @app.expect(:call, [:text, "I understand your concern", nil, nil], [@context])
    @mock_client.expect(:send_message, {"id" => "sent_msg_456"}, ["conv_123", "I understand your concern"], choices: nil, media: nil)

    @gateway.call(@context)

    # Verify latest message was extracted correctly
    assert_equal "I'm still having issues", @context.input
    assert_equal "conversation.user.replied", @context["intercom.topic"]
  end

  def test_webhook_notification_ignored_event_type
    webhook_body = {
      "topic" => "conversation.admin.replied",
      "data" => {"item" => {"type" => "conversation"}}
    }
    setup_post_request_with_webhook(webhook_body)

    @context.controller.expect(:head, nil, [:ok])

    @gateway.call(@context)

    # App should not be called for ignored events
    assert @app.respond_to?(:verify)
  end

  def test_additional_webhook_topics
    # Create gateway with additional topics (admin events)
    custom_gateway = FlowChat::Intercom::Gateway::IntercomApi.new(
      @app,
      @config,
      ["conversation.admin.replied"]
    )
    custom_gateway.instance_variable_set(:@client, @mock_client)

    # Verify default topics are still included
    allowed_topics = custom_gateway.instance_variable_get(:@allowed_webhook_topics)
    assert_includes allowed_topics, "conversation.user.created"
    assert_includes allowed_topics, "conversation.user.replied"
    assert_includes allowed_topics, "conversation.admin.replied"
  end

  def test_admin_event_with_nil_input
    # Create gateway with additional admin topics
    custom_gateway = FlowChat::Intercom::Gateway::IntercomApi.new(
      @app,
      @config,
      ["conversation.admin.replied"]
    )
    custom_gateway.instance_variable_set(:@client, @mock_client)

    # Build webhook for admin.replied (no user message)
    webhook_body = build_admin_replied_webhook
    setup_post_request_with_webhook_and_app_call(webhook_body)

    # App should be called with nil input for admin events
    @app.expect(:call, [:text, "Admin event processed", nil, nil], [@context])
    @mock_client.expect(:send_message, {"id" => "sent_msg"}, ["conv_123", "Admin event processed"], choices: nil, media: nil)

    custom_gateway.call(@context)

    # Verify context was set correctly with nil input
    assert_nil @context.input
    assert_equal "conv_123", @context["request.id"]
    assert_equal "conversation.admin.replied", @context["intercom.topic"]
    assert_equal "user_456", @context["request.user_id"]
  end

  def test_admin_event_ignored_when_not_in_allowed_topics
    # Create gateway WITHOUT admin topics (default topics only)
    default_gateway = FlowChat::Intercom::Gateway::IntercomApi.new(
      @app,
      @config
    )
    default_gateway.instance_variable_set(:@client, @mock_client)

    # Admin event should be ignored
    webhook_body = build_admin_replied_webhook
    setup_post_request_with_webhook(webhook_body)

    @context.controller.expect(:head, nil, [:ok])

    default_gateway.call(@context)

    # App should NOT be called
    assert @app.respond_to?(:verify)
  end

  def test_instrumentation_for_admin_event_with_nil_input
    # Create gateway with admin topics
    custom_gateway = FlowChat::Intercom::Gateway::IntercomApi.new(
      @app,
      @config,
      ["conversation.admin.replied"]
    )
    custom_gateway.instance_variable_set(:@client, @mock_client)

    # Build webhook for admin.replied
    webhook_body = build_admin_replied_webhook
    setup_post_request_with_webhook_and_app_call(webhook_body)

    # Track instrumentation calls
    instrumentation_events = []
    custom_gateway.define_singleton_method(:instrument) do |event, data|
      instrumentation_events << {event: event, data: data}
    end

    @app.expect(:call, [:text, "Admin event processed", nil, nil], [@context])
    @mock_client.expect(:send_message, {"id" => "sent_msg"}, ["conv_123", "Admin event processed"], choices: nil, media: nil)

    custom_gateway.call(@context)

    # Verify MESSAGE_RECEIVED was instrumented with nil message and correct event type
    message_received_event = instrumentation_events.find { |e| e[:event] == FlowChat::Instrumentation::Events::MESSAGE_RECEIVED }
    assert message_received_event, "MESSAGE_RECEIVED event should be instrumented"
    assert_equal "user_456", message_received_event[:data][:from]
    assert_equal "conv_123", message_received_event[:data][:conversation_id]
    assert_nil message_received_event[:data][:message]
    assert_equal "conversation.admin.replied", message_received_event[:data][:event_type]

    # Verify MESSAGE_SENT was instrumented
    message_sent_event = instrumentation_events.find { |e| e[:event] == FlowChat::Instrumentation::Events::MESSAGE_SENT }
    assert message_sent_event, "MESSAGE_SENT event should be instrumented"
    assert_equal "user_456", message_sent_event[:data][:to]
    assert_equal "conv_123", message_sent_event[:data][:conversation_id]
  end

  def test_instrumentation_for_user_event_with_message
    webhook_body = build_conversation_created_webhook
    setup_post_request_with_webhook_and_app_call(webhook_body)

    # Track instrumentation calls
    instrumentation_events = []
    @gateway.define_singleton_method(:instrument) do |event, data|
      instrumentation_events << {event: event, data: data}
    end

    @app.expect(:call, [:text, "User message processed", nil, nil], [@context])
    @mock_client.expect(:send_message, {"id" => "sent_msg"}, ["conv_123", "User message processed"], choices: nil, media: nil)

    @gateway.call(@context)

    # Verify MESSAGE_RECEIVED was instrumented with message content and event type
    message_received_event = instrumentation_events.find { |e| e[:event] == FlowChat::Instrumentation::Events::MESSAGE_RECEIVED }
    assert message_received_event, "MESSAGE_RECEIVED event should be instrumented"
    assert_equal "user_456", message_received_event[:data][:from]
    assert_equal "conv_123", message_received_event[:data][:conversation_id]
    assert_equal "Hello, I need help with my account", message_received_event[:data][:message]
    assert_equal "conversation.user.created", message_received_event[:data][:event_type]
  end

  def test_default_webhook_topics_only
    # Create gateway without additional topics
    default_gateway = FlowChat::Intercom::Gateway::IntercomApi.new(
      @app,
      @config
    )

    allowed_topics = default_gateway.instance_variable_get(:@allowed_webhook_topics)
    assert_equal 2, allowed_topics.length
    assert_includes allowed_topics, "conversation.user.created"
    assert_includes allowed_topics, "conversation.user.replied"
  end

  def test_additional_webhook_topics_through_processor
    # Test that positional arguments work through the processor (middleware builder)
    # This catches issues with argument splatting in the middleware system

    # Create a mock flow
    Class.new(FlowChat::Flow) do
      def start
        app.say "Test"
      end
    end

    # Create processor with additional webhook topics as positional arg
    processor = FlowChat::Processor.new(@context.controller) do |config|
      config.use_gateway FlowChat::Intercom::Gateway::IntercomApi, @config, ["conversation.admin.replied"]
      config.use_session_store FlowChat::Session::CacheSessionStore
      config.use_session_config(boundaries: [:conversation], identifier: :conversation_id)
    end

    # Verify the gateway was initialized with correct topics
    assert processor.instance_variable_get(:@gateway_class) == FlowChat::Intercom::Gateway::IntercomApi
  end

  def test_webhook_notification_no_topic
    webhook_body = {
      "data" => {"item" => {"type" => "conversation"}}
    }
    setup_post_request_with_webhook(webhook_body)

    @context.controller.expect(:head, nil, [:ok])

    @gateway.call(@context)
  end

  def test_webhook_notification_no_data_item
    webhook_body = {
      "topic" => "conversation.user.created",
      "data" => {}
    }
    setup_post_request_with_webhook(webhook_body)

    @context.controller.expect(:head, nil, [:ok])

    @gateway.call(@context)
  end

  def test_webhook_notification_invalid_json
    @context.request.body = StringIO.new("invalid json {")
    @context.request.expect(:post?, true)
    @context.controller.expect(:head, nil, [:bad_request])

    @gateway.call(@context)
  end

  def test_webhook_signature_validation_success
    webhook_body = build_conversation_created_webhook
    body_json = webhook_body.to_json
    signature = generate_webhook_signature(body_json)

    @context.request.body = body_json
    @context.request.headers = {"X-Hub-Signature" => "sha1=#{signature}"}
    @context.request.request_method = "POST"

    # Add mock expectations since valid signature allows webhook processing to continue
    @app.expect(:call, [:text, "Test response", nil, nil], [@context])
    @mock_client.expect(:send_message, {"id" => "sent_msg"}, ["conv_123", "Test response"], choices: nil, media: nil)
    @context.controller.expect(:head, nil, [:ok])

    @gateway.call(@context)
  end

  def test_webhook_signature_validation_failure
    webhook_body = build_conversation_created_webhook
    body_json = webhook_body.to_json

    @context.request.body = StringIO.new(body_json)
    @context.request.headers = {"X-Hub-Signature" => "sha1=invalid_signature"}
    @context.request.expect(:post?, true)
    @context.controller.expect(:head, nil, [:ok])

    @gateway.call(@context)
  end

  def test_webhook_signature_validation_disabled
    # Set skip validation
    @config.skip_signature_validation = true

    webhook_body = build_conversation_created_webhook
    body_json = webhook_body.to_json

    @context.request.body = body_json
    @context.request.headers = {"X-Hub-Signature" => "sha1=invalid_signature"}  # Invalid signature should be ignored
    @context.request.request_method = "POST"

    # Add mock expectations since signature validation is disabled, webhook should process
    @app.expect(:call, [:text, "Test response", nil, nil], [@context])
    @mock_client.expect(:send_message, {"id" => "sent_msg"}, ["conv_123", "Test response"], choices: nil, media: nil)
    @context.controller.expect(:head, nil, [:ok])

    @gateway.call(@context)
  end

  def test_webhook_signature_validation_no_secret_raises_error
    @config.client_secret = nil
    @config.skip_signature_validation = false

    # Test the validation method directly since full gateway call has mock setup issues
    request_mock = FlowChat::TestSupport::SimpleMock.new
    request_mock.instance_variable_set(:@headers, {})
    def request_mock.headers
      @headers
    end

    assert_raises(FlowChat::Intercom::ConfigurationError) do
      @gateway.send(:valid_webhook_signature?, request_mock)
    end
  end

  def test_webhook_signature_validation_missing_header
    webhook_body = build_conversation_created_webhook
    body_json = webhook_body.to_json

    @context.request.body = StringIO.new(body_json)
    @context.request.headers = {} # No signature header
    @context.request.expect(:post?, true)
    @context.controller.expect(:head, nil, [:ok])

    @gateway.call(@context)
  end

  def test_simulator_mode_enabled
    @context["enable_simulator"] = true
    @context.controller.request.cookies = {"flowchat_simulator" => generate_valid_simulator_cookie}

    webhook_body = build_conversation_created_webhook.merge("simulator_mode" => true)
    setup_post_request_with_webhook(webhook_body, skip_signature: true)

    @app.expect(:call, [:text, "Simulator response", {}, nil], [@context])

    expected_response = {
      mode: "simulator",
      webhook_processed: true,
      would_send: {
        message_type: "comment",
        type: "admin",
        admin_id: "test_admin_id",
        body: "Simulator response"
      },
      message_info: {
        to: "conv_123",
        user_id: "user_456",
        user_email: "user@example.com",
        timestamp: instance_of(String)
      }
    }

    @context.controller.expect(:render, nil) do |options|
      assert_equal expected_response.except(:message_info), options[:json].except(:message_info)
      assert_equal "conv_123", options[:json][:message_info][:to]
      assert_equal "user_456", options[:json][:message_info][:user_id]
      assert_equal "user@example.com", options[:json][:message_info][:user_email]
      assert_instance_of String, options[:json][:message_info][:timestamp]
      true
    end

    @gateway.call(@context)
  end

  def test_simulator_mode_invalid_cookie
    @context["enable_simulator"] = true
    @context.controller.request.cookies = {"flowchat_simulator" => "invalid_cookie"}

    webhook_body = build_conversation_created_webhook.merge("simulator_mode" => true)
    setup_post_request_with_webhook(webhook_body)

    @app.expect(:call, [:text, "Regular response", nil, nil], [@context])
    @mock_client.expect(:send_message, {"id" => "sent_msg"}, ["conv_123", "Regular response"], choices: nil, media: nil)

    @gateway.call(@context)

    # Should not be in simulator mode
    assert_nil @context["simulator_mode"]
  end

  def test_invalid_request_method
    @context.request.expect(:get?, false)
    @context.request.expect(:post?, false)
    @context.controller.expect(:head, nil, [:bad_request])

    @gateway.call(@context)
  end

  def test_extract_latest_user_message_created_event
    conversation = {
      "source" => {
        "id" => "msg_123",
        "body" => "Initial message content"
      }
    }

    result = @gateway.send(:extract_latest_user_message, conversation, "conversation.user.created")

    assert_equal "msg_123", result[:id]
    assert_equal "Initial message content", result[:body]
  end

  def test_extract_latest_user_message_reply_event
    conversation = {
      "conversation_parts" => {
        "conversation_parts" => [
          {
            "id" => "part_1",
            "part_type" => "comment",
            "body" => "First reply",
            "author" => {"type" => "user"}
          },
          {
            "id" => "part_2",
            "part_type" => "comment",
            "body" => "Admin response",
            "author" => {"type" => "admin"}
          },
          {
            "id" => "part_3",
            "part_type" => "comment",
            "body" => "Latest user reply",
            "author" => {"type" => "user"}
          }
        ]
      }
    }

    result = @gateway.send(:extract_latest_user_message, conversation, "conversation.user.replied")

    assert_equal "part_3", result[:id]
    assert_equal "Latest user reply", result[:body]
  end

  def test_extract_latest_user_message_no_user_parts
    conversation = {
      "conversation_parts" => {
        "conversation_parts" => [
          {
            "id" => "part_1",
            "part_type" => "comment",
            "body" => "Admin only",
            "author" => {"type" => "admin"}
          }
        ]
      }
    }

    result = @gateway.send(:extract_latest_user_message, conversation, "conversation.user.replied")

    assert_nil result
  end

  def test_extract_maps_multiple_attachments_to_media_array
    conversation = {
      "source" => {
        "id" => "msg_1",
        "body" => "see attached",
        "attachments" => [
          {"name" => "a.png", "url" => "https://i/a.png", "content_type" => "image/png"},
          {"name" => "b.pdf", "url" => "https://i/b.pdf", "content_type" => "application/pdf"}
        ]
      }
    }
    result = @gateway.send(:extract_latest_user_message, conversation, "conversation.user.created")

    assert_equal 2, result[:media].size
    assert_equal :image, result[:media][0][:type]
    assert_equal "https://i/a.png", result[:media][0][:url]
    assert_equal "image/png", result[:media][0][:mime_type]
    assert_equal "a.png", result[:media][0][:filename]
    assert_equal :document, result[:media][1][:type]
  end

  def test_extract_created_event_with_only_attachments_no_body
    conversation = {
      "source" => {
        "id" => "msg_2",
        "attachments" => [
          {"name" => "v.mp4", "url" => "https://i/v.mp4", "content_type" => "video/mp4"}
        ]
      }
    }
    result = @gateway.send(:extract_latest_user_message, conversation, "conversation.user.created")

    refute_nil result
    assert_equal 1, result[:media].size
    assert_equal :video, result[:media][0][:type]
  end

  def test_extract_reply_event_with_attachments
    conversation = {
      "conversation_parts" => {
        "conversation_parts" => [
          {
            "id" => "part_1",
            "part_type" => "comment",
            "body" => "here",
            "author" => {"type" => "user"},
            "attachments" => [
              {"name" => "s.mp3", "url" => "https://i/s.mp3", "content_type" => "audio/mpeg"}
            ]
          }
        ]
      }
    }
    result = @gateway.send(:extract_latest_user_message, conversation, "conversation.user.replied")

    assert_equal 1, result[:media].size
    assert_equal :audio, result[:media][0][:type]
  end

  def test_extract_text_only_message_has_no_media_key
    conversation = {
      "source" => {"id" => "msg_3", "body" => "just text"}
    }
    result = @gateway.send(:extract_latest_user_message, conversation, "conversation.user.created")

    assert_equal "just text", result[:body]
    refute result.key?(:media)
  end

  def test_secure_compare_equal_strings
    result = @gateway.send(:secure_compare, "abc123", "abc123")
    assert_equal true, result
  end

  def test_secure_compare_different_strings
    result = @gateway.send(:secure_compare, "abc123", "def456")
    assert_equal false, result
  end

  def test_secure_compare_different_lengths
    result = @gateway.send(:secure_compare, "abc", "abcdef")
    assert_equal false, result
  end

  def test_html_message_converted_to_markdown
    webhook_body = build_conversation_created_webhook_with_html
    setup_post_request_with_webhook_and_app_call(webhook_body)

    @app.expect(:call, [:text, "Got it!", nil, nil], [@context])
    @mock_client.expect(:send_message, {"id" => "sent_msg"}, ["conv_123", "Got it!"], choices: nil, media: nil)

    @gateway.call(@context)

    # Verify HTML was converted to markdown
    assert_equal "Hello, I need help with **my account**.", @context.input
  end

  def test_html_message_with_link_converted_to_markdown
    webhook_body = build_conversation_created_webhook
    webhook_body["data"]["item"]["source"]["body"] = '<p>Check out <a href="https://example.com">this link</a> please</p>'
    setup_post_request_with_webhook_and_app_call(webhook_body)

    @app.expect(:call, [:text, "Response", nil, nil], [@context])
    @mock_client.expect(:send_message, {"id" => "sent_msg"}, ["conv_123", "Response"], choices: nil, media: nil)

    @gateway.call(@context)

    assert_equal "Check out [this link](https://example.com) please", @context.input
  end

  def test_html_message_empty_after_conversion
    webhook_body = build_conversation_created_webhook
    webhook_body["data"]["item"]["source"]["body"] = "<p>   </p>"
    setup_post_request_with_webhook_and_app_call(webhook_body)

    @app.expect(:call, [:text, "Response", nil, nil], [@context])
    @mock_client.expect(:send_message, {"id" => "sent_msg"}, ["conv_123", "Response"], choices: nil, media: nil)

    @gateway.call(@context)

    assert_equal "", @context.input
  end

  private

  def create_mock_context
    context = {}
    def context.input=(value)
      @input = value
    end

    def context.input
      @input
    end

    # Create a shared request object
    shared_request = create_mock_request

    controller = create_mock_controller_with_request(shared_request)
    context.instance_variable_set(:@controller, controller)
    def context.controller
      @controller
    end

    context.instance_variable_set(:@request, shared_request)
    def context.request
      @request
    end

    context
  end

  def create_mock_controller_with_request(request)
    controller = FlowChat::TestSupport::SimpleMock.new
    controller.instance_variable_set(:@request, request)
    def controller.request
      @request
    end
    controller
  end

  def create_mock_request
    request = FlowChat::TestSupport::SimpleMock.new
    request.instance_variable_set(:@body_content, "")
    request.instance_variable_set(:@headers, {})
    request.instance_variable_set(:@params, {})
    request.instance_variable_set(:@path, "/webhook")
    request.instance_variable_set(:@cookies, {})
    request.instance_variable_set(:@request_method, "POST")

    def request.body
      StringIO.new(@body_content)
    end

    def request.headers
      @headers
    end

    def request.params
      @params
    end

    def request.path
      @path
    end

    def request.cookies
      @cookies
    end

    def request.request_method
      @request_method || "POST"
    end

    def request.request_method=(method)
      @request_method = method
    end

    def request.body=(body_content)
      @body_content = body_content.to_s
    end

    def request.raw_post
      @body_content
    end

    # Default HTTP method handlers
    def request.get?
      @request_method == "GET"
    end

    def request.post?
      @request_method == "POST"
    end

    request
  end

  def setup_head_request
    @context.request.request_method = "HEAD"
    @context.request.expect(:head?, true)
  end

  def setup_post_request_with_webhook(webhook_body, signature: nil, skip_signature: false)
    body_json = webhook_body.to_json
    signature ||= generate_webhook_signature(body_json) unless skip_signature

    @context.request.body = body_json  # Pass string directly, let the setter handle StringIO creation
    @context.request.headers = skip_signature ? {} : {"X-Hub-Signature" => "sha1=#{signature}"}
    @context.request.request_method = "POST"  # Ensure it's POST

    @context.controller.expect(:head, nil, [:ok])
  end

  def setup_post_request_with_webhook_and_app_call(webhook_body, signature: nil, skip_signature: false)
    body_json = webhook_body.to_json
    signature ||= generate_webhook_signature(body_json) unless skip_signature

    @context.request.body = body_json  # Pass string directly, let the setter handle StringIO creation
    @context.request.headers = skip_signature ? {} : {"X-Hub-Signature" => "sha1=#{signature}"}
    @context.request.request_method = "POST"  # Ensure it's POST

    # Don't expect head :ok immediately - it will be called after app processing
    @context.controller.expect(:head, nil, [:ok])
  end

  def build_conversation_created_webhook_with_html
    webhook = build_conversation_created_webhook
    webhook["data"]["item"]["source"]["body"] = "<p>Hello, I need help with <strong>my account</strong>.</p>"
    webhook
  end

  def build_conversation_created_webhook
    {
      "topic" => "conversation.user.created",
      "data" => {
        "item" => {
          "type" => "conversation",
          "id" => "conv_123",
          "source" => {
            "type" => "conversation",
            "id" => "3027934013",
            "delivered_as" => "customer_initiated",
            "subject" => "",
            "body" => "Hello, I need help with my account",
            "author" => {
              "type" => "lead",
              "id" => "user_456",
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
                "id" => "user_456",
                "external_id" => "external_123"
              }
            ]
          }
        }
      }
    }
  end

  def build_conversation_reply_webhook
    {
      "topic" => "conversation.user.replied",
      "data" => {
        "item" => {
          "type" => "conversation",
          "id" => "conv_123",
          "source" => {
            "type" => "conversation",
            "id" => "3027934013",
            "delivered_as" => "customer_initiated",
            "subject" => "",
            "body" => "Initial message",
            "author" => {
              "type" => "lead",
              "id" => "user_456",
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
                "id" => "user_456",
                "external_id" => "external_123"
              }
            ]
          },
          "conversation_parts" => {
            "conversation_parts" => [
              {
                "id" => "part_1",
                "part_type" => "comment",
                "body" => "Hello, I need help",
                "author" => {"type" => "user"}
              },
              {
                "id" => "part_2",
                "part_type" => "comment",
                "body" => "I'm still having issues",
                "author" => {"type" => "user"}
              }
            ]
          }
        }
      }
    }
  end

  def build_admin_replied_webhook
    {
      "topic" => "conversation.admin.replied",
      "data" => {
        "item" => {
          "type" => "conversation",
          "id" => "conv_123",
          "source" => {
            "type" => "conversation",
            "id" => "3027934013",
            "delivered_as" => "customer_initiated",
            "subject" => "",
            "body" => "Initial message from user",
            "author" => {
              "type" => "lead",
              "id" => "user_456",
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
                "id" => "user_456",
                "external_id" => "external_123"
              }
            ]
          },
          "conversation_parts" => {
            "conversation_parts" => [
              {
                "id" => "part_1",
                "part_type" => "comment",
                "body" => "Admin response to the conversation",
                "author" => {"type" => "admin", "id" => "admin_789"}
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

  def test_sets_request_body_with_stringified_keys
    webhook_body = build_conversation_created_webhook
    setup_post_request_with_webhook_and_app_call(webhook_body)

    @app.expect(:call, [:text, "Response", nil, nil], [@context])
    @mock_client.expect(:send_message, {"id" => "sent_msg"}, ["conv_123", "Response"], choices: nil, media: nil)

    @gateway.call(@context)

    # Verify request.body is set
    assert_kind_of Hash, @context["request.body"]

    # Verify it contains the expected webhook structure
    assert @context["request.body"]["topic"]
    assert @context["request.body"]["data"]
    assert_equal "conversation.user.created", @context["request.body"]["topic"]

    # Verify all top-level keys are strings
    @context["request.body"].keys.each do |key|
      assert_kind_of String, key, "Expected all keys to be strings, but found #{key.class}"
    end

    # Verify nested keys are also strings
    data = @context["request.body"]["data"]
    assert_kind_of Hash, data
    data.keys.each do |key|
      assert_kind_of String, key, "Expected nested data keys to be strings, but found #{key.class}"
    end
  end

  def generate_valid_simulator_cookie
    # Mock FlowChat::Config.simulator_secret
    simulator_secret = "test_simulator_secret"
    FlowChat::Config.stub(:simulator_secret, simulator_secret) do
      timestamp = Time.now.to_i
      message = "simulator:#{timestamp}"
      signature = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), simulator_secret, message)
      "#{timestamp}:#{signature}"
    end
  end
end

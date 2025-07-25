require "test_helper"
require "webmock/minitest"

class IntercomIntegrationTest < Minitest::Test
  def setup
    # Set up configuration
    @config = FlowChat::Intercom::Configuration.new("test")
    @config.access_token = "test_access_token"
    @config.client_secret = "test_client_secret"
    @config.admin_id = "test_admin_id"

    # Enable WebMock
    WebMock.enable!
  end

  def teardown
    # Clean up
    WebMock.disable!
    WebMock.reset!
  end

  def test_end_to_end_conversation_flow
    # Set up a simple FlowChat app
    app = create_simple_flowchat_app

    # Create gateway
    gateway = FlowChat::Intercom::Gateway::IntercomApi.new(app, @config)

    # Mock context (simulating Rails controller)
    context = create_mock_context

    # Simulate incoming webhook
    webhook_body = build_test_webhook
    setup_webhook_request(context, webhook_body)

    # Mock Intercom API response for sending message
    stub_intercom_send_message_api

    # Process the webhook
    gateway.call(context)

    # Verify the message was sent to Intercom
    assert_requested :post, "https://api.intercom.io/conversations/conv_123/reply",
      body: {
        message_type: "comment",
        type: "admin",
        admin_id: "test_admin_id",
        body: "Welcome! You said: Hello, I need help\n\nPlease choose:\n1. Get Support\n2. View Account\n\nReply with the number of your choice."
      }.to_json
  end

  def test_configuration_to_client_integration
    # Test that configuration properly flows through to client
    client = FlowChat::Intercom::Client.new(@config)

    # Mock API call
    stub_request(:post, "https://api.intercom.io/conversations/test_conv/reply")
      .with(
        headers: {
          "Authorization" => "Bearer test_access_token",
          "Content-Type" => "application/json",
          "Accept" => "application/json",
          "Intercom-Version" => "2.11"
        }
      )
      .to_return(status: 200, body: {"id" => "msg_123"}.to_json)

    # Send message
    result = client.reply_to_conversation("test_conv", "Test message")

    refute_nil result
    assert_equal "msg_123", result["id"]
  end

  def test_client_to_conversation_manager_integration
    # Test that client methods work properly with conversation manager
    client = FlowChat::Intercom::Client.new(@config)
    manager = FlowChat::Intercom::ConversationManager.new(client, "conv_123")

    # Mock multiple API calls
    stub_request(:post, "https://api.intercom.io/conversations/conv_123/reply")
      .with(body: hash_including(message_type: "assignment"))
      .to_return(status: 200, body: {"id" => "assignment_123"}.to_json)

    stub_request(:post, "https://api.intercom.io/conversations/conv_123/tags")
      .with(body: {name: "test_tag"}.to_json)
      .to_return(status: 200, body: {"id" => "tag_123", "name" => "test_tag"}.to_json)

    stub_request(:post, "https://api.intercom.io/conversations/conv_123/reply")
      .with(body: hash_including(message_type: "comment", admin_id: "test_admin_id"))
      .to_return(status: 200, body: {"id" => "msg_123"}.to_json)

    # Execute multiple operations
    assign_result = manager.assign_conversation("admin_456")
    tag_result = manager.add_tag("test_tag")
    reply_result = manager.send_reply("Hello from bot!")

    assert_equal true, assign_result
    assert_equal true, tag_result
    assert_equal true, reply_result
  end

  def test_renderer_integration_with_gateway
    # Test that renderer properly formats messages for the API
    app = lambda do |context|
      [:selection, "Choose an option:", {"1" => "Option 1", "2" => "Option 2"}, nil]
    end

    gateway = FlowChat::Intercom::Gateway::IntercomApi.new(app, @config)
    context = create_mock_context

    webhook_body = build_test_webhook
    setup_webhook_request(context, webhook_body)

    # Mock the API call to verify the rendered message
    expected_body = "Choose an option:\n\nPlease choose:\n1. Option 1\n2. Option 2\n\nReply with the number of your choice."

    stub_request(:post, "https://api.intercom.io/conversations/conv_123/reply")
      .with(
        body: {
          message_type: "comment",
          type: "admin",
          admin_id: "test_admin_id",
          body: expected_body
        }.to_json
      )
      .to_return(status: 200, body: {"id" => "msg_123"}.to_json)

    gateway.call(context)

    # Verify the request was made with properly rendered content
    assert_requested :post, "https://api.intercom.io/conversations/conv_123/reply"
  end

  def test_error_handling_integration
    # Test that errors are properly handled throughout the stack
    client = FlowChat::Intercom::Client.new(@config)
    manager = FlowChat::Intercom::ConversationManager.new(client, "conv_123")

    # Mock API failure
    stub_request(:post, "https://api.intercom.io/conversations/conv_123/reply")
      .to_return(status: 400, body: {"error" => "Invalid request"}.to_json)

    # Test that errors bubble up properly
    result = manager.send_reply("This should fail")

    assert_equal false, result
  end

  def test_webhook_signature_validation_integration
    app = create_simple_flowchat_app
    gateway = FlowChat::Intercom::Gateway::IntercomApi.new(app, @config)
    context = create_mock_context

    webhook_body = build_test_webhook
    body_json = webhook_body.to_json

    # Generate correct signature
    signature = OpenSSL::HMAC.hexdigest(
      OpenSSL::Digest.new("sha1"),
      @config.client_secret,
      body_json
    )

    # Set up request with valid signature
    context.request.body = StringIO.new(body_json)
    context.request.headers = {"X-Hub-Signature" => "sha1=#{signature}"}

    # Mock successful API call
    stub_intercom_send_message_api

    # Process webhook - should succeed
    gateway.call(context)

    # Verify API was called (webhook was processed)
    assert_requested :post, "https://api.intercom.io/conversations/conv_123/reply"
  end

  def test_configuration_validation_integration
    # Test that invalid configuration prevents operations
    invalid_config = FlowChat::Intercom::Configuration.new("invalid")
    # Don't set required fields

    assert_equal false, invalid_config.valid?

    # Should be able to create client but operations may fail
    client = FlowChat::Intercom::Client.new(invalid_config)
    assert_instance_of FlowChat::Intercom::Client, client
  end

  private

  def create_simple_flowchat_app
    lambda do |context|
      user_message = context.input
      choices = {"support" => "Get Support", "account" => "View Account"}
      [:selection, "Welcome! You said: #{user_message}", choices, nil]
    end
  end

  def create_mock_context
    context = Object.new
    def context.input=(value)
      @input = value
    end

    def context.input
      @input
    end

    def context.[]=(key, value)
      @context_hash ||= {}
      @context_hash[key] = value
    end

    def context.[](key)
      @context_hash ||= {}
      @context_hash[key]
    end

    # Mock controller
    controller = Object.new
    request = create_mock_request

    controller.instance_variable_set(:@request, request)
    def controller.request
      @request
    end

    def controller.head(*args)
      nil
    end

    # Mock response for streaming
    response = FlowChat::TestSupport::MockResponse.new
    controller.instance_variable_set(:@response, response)
    def controller.response
      @response
    end

    context.instance_variable_set(:@controller, controller)
    def context.controller
      @controller
    end

    context.instance_variable_set(:@request, request)
    def context.request
      @request
    end

    context
  end

  def create_mock_request
    request = Object.new
    request.instance_variable_set(:@body, StringIO.new)
    request.instance_variable_set(:@headers, {})
    request.instance_variable_set(:@path, "/webhook")

    def request.body
      @body
    end

    def request.body=(value)
      @body = value
    end

    def request.headers
      @headers
    end

    def request.headers=(value)
      @headers = value
    end

    def request.path
      @path
    end

    def request.post?
      true
    end

    def request.get?
      false
    end

    def request.head?
      false
    end

    def request.request_method
      "POST"
    end

    request
  end

  def build_test_webhook
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
            "body" => "Hello, I need help",
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

  def setup_webhook_request(context, webhook_body)
    body_json = webhook_body.to_json
    signature = OpenSSL::HMAC.hexdigest(
      OpenSSL::Digest.new("sha1"),
      @config.client_secret,
      body_json
    )

    context.request.body = StringIO.new(body_json)
    context.request.headers = {"X-Hub-Signature" => "sha1=#{signature}"}
  end

  def stub_intercom_send_message_api
    stub_request(:post, "https://api.intercom.io/conversations/conv_123/reply")
      .to_return(status: 200, body: {"id" => "msg_sent_123"}.to_json)
  end
end

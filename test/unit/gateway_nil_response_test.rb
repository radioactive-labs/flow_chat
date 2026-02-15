require "test_helper"
require "webmock/minitest"

class GatewayNilResponseTest < Minitest::Test
  def setup
    WebMock.enable!
    WebMock.reset!

    # Stub external API endpoints with specific patterns
    stub_request(:post, %r{graph\.facebook\.com/v\d+\.\d+/\d+/messages})
      .to_return(status: 200, body: {"messages" => [{"id" => "msg_123"}]}.to_json)

    stub_request(:post, %r{api\.intercom\.io/conversations/[^/]+/reply})
      .to_return(status: 200, body: {"type" => "conversation", "id" => "123"}.to_json)
  end

  def teardown
    WebMock.disable!
    WebMock.reset!
  end

  # ==========================================================================
  # HTTP Simple Gateway
  # ==========================================================================

  def test_http_simple_gateway_handles_nil_response
    controller = build_mock_http_controller
    context = FlowChat::Context.new
    context["controller"] = controller

    app = ->(ctx) { nil }
    gateway = FlowChat::Http::Gateway::Simple.new(app, {session_id: "test_123", user_id: "user_456"})
    gateway.call(context)

    response = controller.rendered_response
    assert_equal :skip, response[:json][:type]
    assert_equal "test_123", response[:json][:session_id]
    assert_equal "user_456", response[:json][:user_id]
    assert response[:json][:timestamp]
  end

  # ==========================================================================
  # USSD Nalo Gateway
  # ==========================================================================

  def test_ussd_nalo_gateway_renders_empty_message_for_nil_response
    controller = build_mock_ussd_controller
    context = FlowChat::Context.new
    context["controller"] = controller

    app = ->(ctx) { nil }
    gateway = FlowChat::Ussd::Gateway::Nalo.new(app)
    gateway.call(context)

    response = controller.rendered_response
    assert response[:json], "Expected JSON response"
    assert_equal "session_123", response[:json][:USERID]
    assert_equal "233200000000", response[:json][:MSISDN]
    assert_equal "", response[:json][:MSG], "MSG should be empty string for nil prompt"
  end

  # ==========================================================================
  # WhatsApp Cloud API Gateway
  # ==========================================================================

  def test_whatsapp_cloud_api_gateway_handles_nil_response
    webhook_body = whatsapp_text_message_payload(text: "hello")
    controller = build_mock_whatsapp_controller(webhook_body: webhook_body)
    context = FlowChat::Context.new
    context["controller"] = controller

    app = ->(ctx) { nil }
    config = build_whatsapp_config

    gateway = FlowChat::Whatsapp::Gateway::CloudApi.new(app, config)
    gateway.call(context)

    assert_equal :ok, controller.last_head_status
    assert_not_requested :post, %r{graph\.facebook\.com/v\d+\.\d+/\d+/messages}
  end

  # ==========================================================================
  # Intercom Gateway
  # ==========================================================================

  def test_intercom_gateway_handles_nil_response
    webhook_body = intercom_user_replied_payload
    controller = build_mock_intercom_controller(webhook_body: webhook_body)
    context = FlowChat::Context.new
    context["controller"] = controller

    app = ->(ctx) { nil }
    config = FlowChat::Intercom::Configuration.new("test")
    config.access_token = "test_token"
    config.skip_signature_validation = true

    gateway = FlowChat::Intercom::Gateway::IntercomApi.new(app, config)
    gateway.call(context)

    assert_equal :ok, controller.last_head_status
    assert_not_requested :post, %r{api\.intercom\.io/conversations/[^/]+/reply}
  end

  private

  def build_whatsapp_config
    config = FlowChat::Whatsapp::Configuration.new("test")
    config.access_token = "test_token"
    config.phone_number_id = "123456"
    config.verify_token = "verify_token"
    config.app_secret = "app_secret"
    config.skip_signature_validation = true
    config
  end
end

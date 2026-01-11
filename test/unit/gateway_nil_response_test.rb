require "test_helper"

class GatewayNilResponseTest < Minitest::Test
  # Test that HTTP Simple gateway handles nil response
  def test_http_simple_gateway_handles_nil_response
    controller = mock_controller_with_request
    context = FlowChat::Context.new
    context["controller"] = controller

    # Mock app that returns nil
    app = ->(ctx) { nil }

    user_params = {session_id: "test_123", user_id: "user_456"}
    gateway = FlowChat::Http::Gateway::Simple.new(app, user_params)
    gateway.call(context)

    # Should render json with :skip type and full response structure
    response = controller.rendered_response
    assert_equal :skip, response[:json][:type]
    assert response[:json][:session_id]
    assert response[:json][:user_id]
    assert response[:json][:timestamp]
  end

  # Test that USSD Nalo gateway does NOT handle nil response
  def test_ussd_nalo_gateway_does_not_handle_nil_response
    skip "USSD is synchronous and MUST return a response - nil handling not supported"
  end

  # Test that WhatsApp CloudApi gateway handles nil response (already had this)
  def test_whatsapp_cloud_api_gateway_handles_nil_response
    skip "WhatsApp gateway has more complex setup - already tested in integration tests"
  end

  # Test that Intercom gateway handles nil response (already had this)
  def test_intercom_gateway_handles_nil_response
    skip "Intercom gateway has more complex setup - already tested in integration tests"
  end

  private

  def mock_controller_with_request(params = {})
    request = OpenStruct.new(
      params: params.with_indifferent_access,
      method: "POST",
      headers: OpenStruct.new({"Content-Type" => "application/json"}),
      host: "test.example.com",
      path: "/test",
      remote_ip: "127.0.0.1",
      body: nil,
      cookies: {}
    )

    request.define_singleton_method(:get?) { method.upcase == "GET" }
    request.define_singleton_method(:post?) { method.upcase == "POST" }
    request.define_singleton_method(:user_agent) { headers["User-Agent"] }

    controller = Object.new
    controller.define_singleton_method(:request) { request }
    controller.define_singleton_method(:rendered_response) { @rendered_response }
    controller.define_singleton_method(:render) do |options|
      @rendered_response = options
      nil
    end

    controller
  end
end

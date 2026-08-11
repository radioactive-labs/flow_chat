require "test_helper"
require_relative "../../../support/test_helpers"

class InstagramSendApiGatewayTest < Minitest::Test
  include FlowChat::TestSupport::TestHelpers

  def setup
    @app = proc { |context| [:text, "Response", nil, nil] }
  end

  def test_expected_webhook_object_on_facebook_login_path
    gateway = build_gateway(login: :facebook)
    assert_equal "instagram", gateway.expected_webhook_object
  end

  def test_expected_webhook_object_on_instagram_login_path
    gateway = build_gateway(login: :instagram)
    assert_equal "instagram", gateway.expected_webhook_object
  end

  # On the Facebook Login path an inbound delivery's entry.id is the linked
  # Page, not the Instagram account, since that is what account_id resolves
  # to for that path. A fresh gateway per call, matching how
  # FlowChat::Processor builds one per request: the gateway memoizes the
  # parsed body for the request's lifetime, so reusing one across two posts
  # would answer the second from the first request's body.
  def test_inbound_delivery_matched_against_page_id_on_facebook_login_path
    accepted_gateway = build_gateway(login: :facebook)
    stub_send(accepted_gateway)
    accepted = post(accepted_gateway, entry_id: "page_1")
    assert_equal "Hello", accepted.input

    rejected_gateway = build_gateway(login: :facebook)
    stub_send(rejected_gateway)
    rejected = post(rejected_gateway, entry_id: "ig_1")
    assert_equal :forbidden, rejected.controller.last_head_status
  end

  # On the Instagram Login path there is no linked Page at all, so the same
  # delivery must instead be checked against the Instagram account id.
  def test_inbound_delivery_matched_against_instagram_account_id_on_instagram_login_path
    accepted_gateway = build_gateway(login: :instagram)
    stub_send(accepted_gateway)
    accepted = post(accepted_gateway, entry_id: "ig_1")
    assert_equal "Hello", accepted.input

    rejected_gateway = build_gateway(login: :instagram)
    stub_send(rejected_gateway)
    rejected = post(rejected_gateway, entry_id: "page_1")
    assert_equal :forbidden, rejected.controller.last_head_status
  end

  private

  def build_gateway(login:, page_id: "page_1", instagram_account_id: "ig_1")
    config = FlowChat::Instagram::Configuration.new(nil)
    config.login = login
    config.page_id = page_id
    config.instagram_account_id = instagram_account_id
    config.access_token = "tok"
    config.verify_token = "verify"
    config.skip_signature_validation = true

    FlowChat::Instagram::Gateway::SendApi.new(@app, config)
  end

  def stub_send(gateway)
    gateway.client.define_singleton_method(:send_message) { |*args, **kwargs| {"message_id" => "mid.sent"} }
  end

  def post(gateway, entry_id:)
    body = {
      "object" => "instagram",
      "entry" => [{
        "id" => entry_id,
        "messaging" => [{
          "sender" => {"id" => "psid_1"},
          "recipient" => {"id" => entry_id},
          "timestamp" => 1_700_000_000,
          "message" => {"mid" => "mid.1", "text" => "Hello"}
        }]
      }]
    }

    context = build_messaging_context(body)
    gateway.call(context)
    context
  end
end

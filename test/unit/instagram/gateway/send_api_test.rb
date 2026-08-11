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

  # Meta's docs do not say definitively whether an Instagram delivery's
  # entry.id carries the linked Page id or the Instagram professional
  # account id, and this is unaffected by which login path the app uses:
  # both ids belong to the one configured account, so either arriving is a
  # legitimate delivery. A fresh gateway per call, matching how
  # FlowChat::Processor builds one per request: the gateway memoizes the
  # parsed body for the request's lifetime, so reusing one across two posts
  # would answer the second from the first request's body.
  def test_inbound_delivery_matches_either_the_page_id_or_the_instagram_account_id_on_facebook_login_path
    page_gateway = build_gateway(login: :facebook)
    stub_send(page_gateway)
    matched_by_page = post(page_gateway, entry_id: "page_1")
    assert_equal "Hello", matched_by_page.input

    ig_gateway = build_gateway(login: :facebook)
    stub_send(ig_gateway)
    matched_by_ig_account = post(ig_gateway, entry_id: "ig_1")
    assert_equal "Hello", matched_by_ig_account.input
  end

  # Same either-id acceptance on the Instagram Login path: which login the
  # app uses only changes which id account_id resolves to for building API
  # URLs, not which id an inbound webhook is allowed to name.
  def test_inbound_delivery_matches_either_the_page_id_or_the_instagram_account_id_on_instagram_login_path
    page_gateway = build_gateway(login: :instagram)
    stub_send(page_gateway)
    matched_by_page = post(page_gateway, entry_id: "page_1")
    assert_equal "Hello", matched_by_page.input

    ig_gateway = build_gateway(login: :instagram)
    stub_send(ig_gateway)
    matched_by_ig_account = post(ig_gateway, entry_id: "ig_1")
    assert_equal "Hello", matched_by_ig_account.input
  end

  # An id naming neither the linked Page nor the Instagram account is still
  # not this configuration's account, regardless of login path.
  def test_inbound_delivery_matching_neither_id_is_rejected
    gateway = build_gateway(login: :facebook)
    stub_send(gateway)
    rejected = post(gateway, entry_id: "someone_elses_account")
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

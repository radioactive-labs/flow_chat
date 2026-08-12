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

  # An Instagram delivery arrives under `object: "instagram"`, which names the
  # Instagram professional account in entry.id. The linked Page is what a send
  # is addressed to and is not a legitimate inbound id, on either login path:
  # accepting it is what let a page-keyed connection look configured while
  # never receiving. A fresh gateway per call, matching how
  # FlowChat::Processor builds one per request: the gateway memoizes the
  # parsed body for the request's lifetime, so reusing one across two posts
  # would answer the second from the first request's body.
  def test_inbound_delivery_names_the_instagram_account_on_facebook_login_path
    ig_gateway = build_gateway(login: :facebook)
    stub_send(ig_gateway)
    assert_equal "Hello", post(ig_gateway, entry_id: "ig_1").input

    page_gateway = build_gateway(login: :facebook)
    stub_send(page_gateway)
    assert_nil post(page_gateway, entry_id: "page_1").input
  end

  # Same id on the Instagram Login path, where there is no Page to confuse it
  # with. Which login the app uses only changes which id account_id resolves to
  # for building API URLs.
  def test_inbound_delivery_names_the_instagram_account_on_instagram_login_path
    ig_gateway = build_gateway(login: :instagram)
    stub_send(ig_gateway)
    assert_equal "Hello", post(ig_gateway, entry_id: "ig_1").input

    page_gateway = build_gateway(login: :instagram)
    stub_send(page_gateway)
    assert_nil post(page_gateway, entry_id: "page_1").input
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

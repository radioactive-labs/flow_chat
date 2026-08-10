require "test_helper"
require_relative "../../support/fake_meta_gateway"

class MetaWebhookVerificationTest < Minitest::Test
  def setup
    @config = OpenStruct.new(verify_token: "test_token")
    @controller = webhook_controller(verify_token: "test_token", challenge: "the_challenge")
    @gateway = FlowChat::TestSupport::FakeMetaGateway.new(@config, controller: @controller)
  end

  def teardown
    @subscribers&.each { |s| ActiveSupport::Notifications.unsubscribe(s) }
  end

  def test_matching_token_renders_the_challenge
    @gateway.send(:handle_verification, nil)

    assert_equal "the_challenge", @controller.rendered_response[:plain]
    assert_nil @controller.last_head_status
  end

  def test_wrong_token_is_forbidden
    @controller = webhook_controller(verify_token: "wrong_token", challenge: "the_challenge")
    @gateway = FlowChat::TestSupport::FakeMetaGateway.new(@config, controller: @controller)

    @gateway.send(:handle_verification, nil)

    assert_equal :forbidden, @controller.last_head_status
    assert_nil @controller.rendered_response
  end

  # The security-relevant case: without the verify_token.present? guard, a
  # missing token on both sides compares equal and anyone could claim the
  # webhook endpoint by asking for the challenge.
  def test_blank_configured_token_is_forbidden_even_when_the_request_token_is_blank
    @config.verify_token = ""
    @controller = webhook_controller(verify_token: "", challenge: "the_challenge")
    @gateway = FlowChat::TestSupport::FakeMetaGateway.new(@config, controller: @controller)

    @gateway.send(:handle_verification, nil)

    assert_equal :forbidden, @controller.last_head_status
    assert_nil @controller.rendered_response
  end

  def test_verified_event_carries_the_platform
    payloads = []
    subscribe("webhook.verified") { |payload| payloads << payload }

    @gateway.send(:handle_verification, nil)

    assert_equal :fake_meta, payloads.first[:platform]
  end

  def test_failed_event_carries_the_platform
    @controller = webhook_controller(verify_token: "wrong_token", challenge: "the_challenge")
    @gateway = FlowChat::TestSupport::FakeMetaGateway.new(@config, controller: @controller)

    payloads = []
    subscribe("webhook.failed") { |payload| payloads << payload }

    @gateway.send(:handle_verification, nil)

    assert_equal :fake_meta, payloads.first[:platform]
  end

  # Each behavior module must stand alone. Before GatewayIdentity existed,
  # WebhookVerification only worked because SignatureValidation happened to be
  # included alongside it and supplied log_tag.
  def test_verification_works_without_signature_validation
    gateway_class = Class.new do
      include FlowChat::Instrumentation
      include FlowChat::Meta::WebhookVerification

      def platform = :test_platform

      def platform_label = "Test"

      def configuration_error_class = FlowChat::Meta::ConfigurationError

      def log_tag = "TestGateway"
    end

    refute gateway_class.include?(FlowChat::Meta::SignatureValidation)

    controller = webhook_controller(verify_token: "tok", challenge: "chal")
    gateway = gateway_class.new
    gateway.instance_variable_set(:@config, OpenStruct.new(verify_token: "tok"))
    gateway.instance_variable_set(:@controller, controller)

    gateway.send(:handle_verification, nil)

    assert_equal "chal", controller.rendered_response[:plain]
  end

  private

  def webhook_controller(verify_token:, challenge:)
    build_mock_http_controller(
      params: {
        "hub.mode" => "subscribe",
        "hub.verify_token" => verify_token,
        "hub.challenge" => challenge
      },
      method: "GET"
    )
  end

  def subscribe(event)
    @subscribers ||= []
    @subscribers << ActiveSupport::Notifications.subscribe("#{event}.flow_chat") do |*args|
      yield ActiveSupport::Notifications::Event.new(*args).payload
    end
  end
end

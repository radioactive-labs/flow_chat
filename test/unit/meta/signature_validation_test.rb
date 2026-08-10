require "test_helper"
require "openssl"
require_relative "../../support/fake_meta_gateway"

class MetaSignatureValidationTest < Minitest::Test
  def setup
    @config = OpenStruct.new(skip_signature_validation: false, app_secret: "test_secret")
    @gateway = FlowChat::TestSupport::FakeMetaGateway.new(@config)
  end

  # The mirror of test_verification_works_without_signature_validation. The shared
  # fake includes both behavior modules, so neither test file proves isolation on
  # its own any more. Each module must stand alone: they are included separately
  # by gateways that need only one.
  def test_signature_validation_works_without_webhook_verification
    gateway_class = Class.new do
      include FlowChat::Meta::SignatureValidation

      def platform = :sig_only
      def platform_label = "SigOnly"
      def configuration_error_class = FlowChat::Meta::ConfigurationError
      def log_tag = "SigOnlyGateway"
    end

    refute gateway_class.include?(FlowChat::Meta::WebhookVerification)

    body = '{"entry":[]}'
    secret = "test_secret"
    signature = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), secret, body)
    request = OpenStruct.new(
      headers: {"X-Hub-Signature-256" => "sha256=#{signature}"},
      body: StringIO.new(body)
    )

    gateway = gateway_class.new
    gateway.instance_variable_set(:@config, OpenStruct.new(skip_signature_validation: false, app_secret: secret))

    assert gateway.send(:valid_webhook_signature?, request)
  end

  def test_whitespace_only_app_secret_raises_configuration_error
    @config.app_secret = "   "

    assert_raises(FlowChat::Meta::ConfigurationError) do
      @gateway.send(:valid_webhook_signature?, nil)
    end
  end

  def test_nil_app_secret_raises_configuration_error
    @config.app_secret = nil

    assert_raises(FlowChat::Meta::ConfigurationError) do
      @gateway.send(:valid_webhook_signature?, nil)
    end
  end

  def test_empty_app_secret_raises_configuration_error_naming_the_platform
    @config.app_secret = ""

    error = assert_raises(FlowChat::Meta::ConfigurationError) do
      @gateway.send(:valid_webhook_signature?, nil)
    end

    assert_match(/\AFakeMeta app_secret is required/, error.message)
  end

  def test_skip_signature_validation_short_circuits_ahead_of_app_secret_check
    @config.app_secret = nil
    @config.skip_signature_validation = true

    assert_equal true, @gateway.send(:valid_webhook_signature?, nil)
  end

  def test_valid_signature_returns_true
    request = build_request(body: '{"hello":"world"}', app_secret: "test_secret")

    assert_equal true, @gateway.send(:valid_webhook_signature?, request)
  end

  def test_mismatched_signature_returns_false
    request = build_request(body: '{"hello":"world"}', signature_override: "sha256=not_the_right_signature")

    assert_equal false, @gateway.send(:valid_webhook_signature?, request)
  end

  def test_missing_header_returns_false
    request = OpenStruct.new(headers: {}, body: StringIO.new('{"hello":"world"}'))

    assert_equal false, @gateway.send(:valid_webhook_signature?, request)
  end

  def test_body_is_left_rewound_after_validation
    request = build_request(body: '{"hello":"world"}', app_secret: "test_secret")

    @gateway.send(:valid_webhook_signature?, request)

    assert_equal 0, request.body.pos
  end

  private

  # Builds a request with a correctly computed X-Hub-Signature-256 header for
  # `body` under `app_secret` (defaulting to @config.app_secret), unless
  # `signature_override` is given instead.
  def build_request(body:, app_secret: nil, signature_override: nil)
    signature_header = signature_override || begin
      digest = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), app_secret || @config.app_secret, body)
      "sha256=#{digest}"
    end

    OpenStruct.new(
      headers: {"X-Hub-Signature-256" => signature_header},
      body: StringIO.new(body)
    )
  end
end

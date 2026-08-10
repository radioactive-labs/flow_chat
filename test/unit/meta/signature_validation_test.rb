require "test_helper"

# A minimal stand-in for a Meta gateway: just enough state (@config) for the
# module to work against, using its default hooks (Meta::ConfigurationError,
# "Meta" label, class-name-derived log tag).
class FakeMetaGateway
  include FlowChat::Meta::SignatureValidation

  def initialize(config)
    @config = config
  end
end

class MetaSignatureValidationTest < Minitest::Test
  def setup
    @config = OpenStruct.new(skip_signature_validation: false, app_secret: "test_secret")
    @gateway = FakeMetaGateway.new(@config)
  end

  def test_whitespace_only_app_secret_raises_configuration_error
    @config.app_secret = "   "

    assert_raises(FlowChat::Meta::ConfigurationError) do
      @gateway.valid_webhook_signature?(nil)
    end
  end

  def test_nil_app_secret_raises_configuration_error
    @config.app_secret = nil

    assert_raises(FlowChat::Meta::ConfigurationError) do
      @gateway.valid_webhook_signature?(nil)
    end
  end

  def test_empty_app_secret_raises_configuration_error
    @config.app_secret = ""

    assert_raises(FlowChat::Meta::ConfigurationError) do
      @gateway.valid_webhook_signature?(nil)
    end
  end

  def test_skip_signature_validation_short_circuits_ahead_of_app_secret_check
    @config.app_secret = nil
    @config.skip_signature_validation = true

    assert_equal true, @gateway.valid_webhook_signature?(nil)
  end
end

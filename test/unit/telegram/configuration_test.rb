require "test_helper"

class FlowChat::Telegram::ConfigurationTest < Minitest::Test
  def setup
    # Clear any existing configurations
    FlowChat::Telegram::Configuration.clear_all!
  end

  def teardown
    # Clean up after each test
    FlowChat::Telegram::Configuration.clear_all!
  end

  def test_initialize_with_name
    config = FlowChat::Telegram::Configuration.new("test")

    assert_equal :test, config.name
    assert_nil config.bot_token
    assert_nil config.secret_token
    assert_equal false, config.skip_signature_validation
  end

  def test_initialize_without_name
    config = FlowChat::Telegram::Configuration.new(nil)

    assert_nil config.name
  end

  def test_register_as
    config = FlowChat::Telegram::Configuration.new(nil)
    config.register_as("production")

    assert_equal :production, config.name
    assert FlowChat::Telegram::Configuration.exists?("production")
  end

  def test_valid_configuration
    config = FlowChat::Telegram::Configuration.new("test")

    # Invalid initially
    assert_equal false, config.valid?

    # Set required fields
    config.bot_token = "123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11"

    # Now valid
    assert_equal true, config.valid?
  end

  def test_invalid_configuration_missing_bot_token
    config = FlowChat::Telegram::Configuration.new("test")

    assert_equal false, config.valid?
  end

  def test_invalid_configuration_empty_bot_token
    config = FlowChat::Telegram::Configuration.new("test")
    config.bot_token = ""

    assert_equal false, config.valid?
  end

  def test_api_base_url
    config = FlowChat::Telegram::Configuration.new("test")
    config.bot_token = "123456:ABC-DEF"

    assert_equal "https://api.telegram.org/bot123456:ABC-DEF", config.api_base_url
  end

  def test_api_base_url_without_token
    config = FlowChat::Telegram::Configuration.new("test")

    assert_nil config.api_base_url
  end

  def test_bot_id
    config = FlowChat::Telegram::Configuration.new("test")
    config.bot_token = "123456789:ABC-DEF1234ghIkl-zyx57W2v1u123ew11"

    assert_equal "123456789", config.bot_id
  end

  def test_bot_id_without_token
    config = FlowChat::Telegram::Configuration.new("test")

    assert_nil config.bot_id
  end

  def test_class_register_and_get
    config = FlowChat::Telegram::Configuration.new("test")
    config.bot_token = "test_token"

    FlowChat::Telegram::Configuration.register("test", config)

    retrieved_config = FlowChat::Telegram::Configuration.get("test")
    assert_equal config, retrieved_config
    assert_equal "test_token", retrieved_config.bot_token
  end

  def test_class_get_nonexistent_configuration
    assert_raises(ArgumentError) do
      FlowChat::Telegram::Configuration.get("nonexistent")
    end
  end

  def test_class_exists
    config = FlowChat::Telegram::Configuration.new("test")
    FlowChat::Telegram::Configuration.register("test", config)

    assert FlowChat::Telegram::Configuration.exists?("test")
    assert_equal false, FlowChat::Telegram::Configuration.exists?("nonexistent")
  end

  def test_class_configuration_names
    config1 = FlowChat::Telegram::Configuration.new("config1")
    config2 = FlowChat::Telegram::Configuration.new("config2")

    FlowChat::Telegram::Configuration.register("config1", config1)
    FlowChat::Telegram::Configuration.register("config2", config2)

    names = FlowChat::Telegram::Configuration.configuration_names
    assert_includes names, :config1
    assert_includes names, :config2
  end

  def test_class_clear_all
    config = FlowChat::Telegram::Configuration.new("test")
    FlowChat::Telegram::Configuration.register("test", config)

    assert FlowChat::Telegram::Configuration.exists?("test")

    FlowChat::Telegram::Configuration.clear_all!

    assert_equal false, FlowChat::Telegram::Configuration.exists?("test")
    assert_empty FlowChat::Telegram::Configuration.configuration_names
  end

  def test_from_credentials_with_rails_credentials
    # Mock Rails credentials structure
    credentials_hash = {
      bot_token: "rails_bot_token",
      secret_token: "rails_secret",
      skip_signature_validation: true
    }

    # Create Rails mock with proper structure
    rails_mock = Object.new
    rails_mock.define_singleton_method(:application) do
      app_mock = Object.new
      app_mock.define_singleton_method(:credentials) do
        creds_mock = Object.new
        creds_mock.define_singleton_method(:telegram) { credentials_hash }
        creds_mock
      end
      app_mock
    end
    # Temporarily define Rails constant
    original_rails = defined?(Rails) ? Rails : nil
    Object.send(:remove_const, :Rails) if defined?(Rails)
    Object.const_set(:Rails, rails_mock)

    config = FlowChat::Telegram::Configuration.from_credentials

    assert_equal "rails_bot_token", config.bot_token
    assert_equal "rails_secret", config.secret_token
    assert_equal true, config.skip_signature_validation
    assert_equal true, config.valid?
  ensure
    # Restore original Rails constant
    Object.send(:remove_const, :Rails) if defined?(Rails)
    Object.const_set(:Rails, original_rails) if original_rails
  end

  def test_from_credentials_with_environment_variables
    # Remove Rails if it exists for this test
    rails_backup = nil
    if defined?(Rails)
      rails_backup = Rails
      Object.send(:remove_const, :Rails)
    end

    # Set environment variables
    ENV["TELEGRAM_BOT_TOKEN"] = "env_bot_token"
    ENV["TELEGRAM_SECRET_TOKEN"] = "env_secret"
    ENV["TELEGRAM_SKIP_SIGNATURE_VALIDATION"] = "true"

    config = FlowChat::Telegram::Configuration.from_credentials

    assert_equal "env_bot_token", config.bot_token
    assert_equal "env_secret", config.secret_token
    assert_equal true, config.skip_signature_validation
    assert config.valid?
  ensure
    # Clean up environment variables
    ENV.delete("TELEGRAM_BOT_TOKEN")
    ENV.delete("TELEGRAM_SECRET_TOKEN")
    ENV.delete("TELEGRAM_SKIP_SIGNATURE_VALIDATION")

    # Restore Rails constant if it existed
    Object.const_set(:Rails, rails_backup) if rails_backup
  end

  def test_send_message_url
    config = FlowChat::Telegram::Configuration.new("test")
    config.bot_token = "123456:ABC-DEF"

    assert_equal "https://api.telegram.org/bot123456:ABC-DEF/sendMessage", config.send_message_url
  end

  def test_set_webhook_url
    config = FlowChat::Telegram::Configuration.new("test")
    config.bot_token = "123456:ABC-DEF"

    assert_equal "https://api.telegram.org/bot123456:ABC-DEF/setWebhook", config.set_webhook_url
  end

  def test_get_webhook_info_url
    config = FlowChat::Telegram::Configuration.new("test")
    config.bot_token = "123456:ABC-DEF"

    assert_equal "https://api.telegram.org/bot123456:ABC-DEF/getWebhookInfo", config.get_webhook_info_url
  end

  def test_delete_webhook_url
    config = FlowChat::Telegram::Configuration.new("test")
    config.bot_token = "123456:ABC-DEF"

    assert_equal "https://api.telegram.org/bot123456:ABC-DEF/deleteWebhook", config.delete_webhook_url
  end
end

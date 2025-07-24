require "test_helper"

class FlowChat::Intercom::ConfigurationTest < Minitest::Test
  def setup
    # Clear any existing configurations
    FlowChat::Intercom::Configuration.clear_all!
  end

  def teardown
    # Clean up after each test
    FlowChat::Intercom::Configuration.clear_all!
  end

  def test_initialize_with_name
    config = FlowChat::Intercom::Configuration.new("test")

    assert_equal :test, config.name
    assert_nil config.access_token
    assert_nil config.client_secret
    assert_nil config.admin_id
    assert_equal false, config.skip_signature_validation
  end

  def test_initialize_without_name
    config = FlowChat::Intercom::Configuration.new(nil)

    assert_nil config.name
  end

  def test_register_as
    config = FlowChat::Intercom::Configuration.new(nil)
    config.register_as("production")

    assert_equal :production, config.name
    assert FlowChat::Intercom::Configuration.exists?("production")
  end

  def test_valid_configuration
    config = FlowChat::Intercom::Configuration.new("test")

    # Invalid initially (returns false, not nil)
    assert_equal false, config.valid?

    # Set required fields
    config.access_token = "test_token"
    config.admin_id = "test_admin_id"

    # Now valid
    assert_equal true, config.valid?
  end

  def test_invalid_configuration_missing_access_token
    config = FlowChat::Intercom::Configuration.new("test")

    assert_equal false, config.valid?
  end

  def test_invalid_configuration_empty_tokens
    config = FlowChat::Intercom::Configuration.new("test")
    config.access_token = ""

    assert_equal false, config.valid?
  end

  def test_api_base_url
    config = FlowChat::Intercom::Configuration.new("test")

    assert_equal "https://api.intercom.io", config.api_base_url
  end

  def test_conversations_url
    config = FlowChat::Intercom::Configuration.new("test")

    assert_equal "https://api.intercom.io/conversations", config.conversations_url
    assert_equal "https://api.intercom.io/conversations/123", config.conversations_url("123")
  end

  def test_conversation_reply_url
    config = FlowChat::Intercom::Configuration.new("test")

    assert_equal "https://api.intercom.io/conversations/123/reply", config.conversation_reply_url("123")
  end

  def test_conversation_parts_url
    config = FlowChat::Intercom::Configuration.new("test")

    assert_equal "https://api.intercom.io/conversations/123/parts", config.conversation_parts_url("123")
  end

  def test_conversation_tags_url
    config = FlowChat::Intercom::Configuration.new("test")

    assert_equal "https://api.intercom.io/conversations/123/tags", config.conversation_tags_url("123")
    assert_equal "https://api.intercom.io/conversations/123/tags/456", config.conversation_tags_url("123", "456")
  end

  def test_admins_url
    config = FlowChat::Intercom::Configuration.new("test")

    assert_equal "https://api.intercom.io/admins", config.admins_url
  end

  def test_api_headers
    config = FlowChat::Intercom::Configuration.new("test")
    config.access_token = "test_token"

    expected_headers = {
      "Authorization" => "Bearer test_token",
      "Content-Type" => "application/json",
      "Accept" => "application/json",
      "Intercom-Version" => "2.11"
    }

    assert_equal expected_headers, config.api_headers
  end

  def test_class_register_and_get
    config = FlowChat::Intercom::Configuration.new("test")
    config.access_token = "test_token"

    FlowChat::Intercom::Configuration.register("test", config)

    retrieved_config = FlowChat::Intercom::Configuration.get("test")
    assert_equal config, retrieved_config
    assert_equal "test_token", retrieved_config.access_token
  end

  def test_class_get_nonexistent_configuration
    assert_raises(ArgumentError, "Intercom configuration 'nonexistent' not found") do
      FlowChat::Intercom::Configuration.get("nonexistent")
    end
  end

  def test_class_exists
    config = FlowChat::Intercom::Configuration.new("test")
    FlowChat::Intercom::Configuration.register("test", config)

    assert FlowChat::Intercom::Configuration.exists?("test")
    assert_equal false, FlowChat::Intercom::Configuration.exists?("nonexistent")
  end

  def test_class_configuration_names
    config1 = FlowChat::Intercom::Configuration.new("config1")
    config2 = FlowChat::Intercom::Configuration.new("config2")

    FlowChat::Intercom::Configuration.register("config1", config1)
    FlowChat::Intercom::Configuration.register("config2", config2)

    names = FlowChat::Intercom::Configuration.configuration_names
    assert_includes names, :config1
    assert_includes names, :config2
  end

  def test_class_clear_all
    config = FlowChat::Intercom::Configuration.new("test")
    FlowChat::Intercom::Configuration.register("test", config)

    assert FlowChat::Intercom::Configuration.exists?("test")

    FlowChat::Intercom::Configuration.clear_all!

    assert_equal false, FlowChat::Intercom::Configuration.exists?("test")
    assert_empty FlowChat::Intercom::Configuration.configuration_names
  end

  def test_from_credentials_with_rails_credentials
    # Mock Rails credentials structure
    credentials_hash = {
      access_token: "rails_token",
      client_secret: "rails_secret",
      admin_id: "rails_admin_id",
      skip_signature_validation: true
    }

    # Create Rails mock with proper structure
    rails_mock = Object.new
    rails_mock.define_singleton_method(:application) do
      app_mock = Object.new
      app_mock.define_singleton_method(:credentials) do
        creds_mock = Object.new
        creds_mock.define_singleton_method(:intercom) { credentials_hash }
        creds_mock
      end
      app_mock
    end

    # Temporarily define Rails constant
    original_rails = defined?(Rails) ? Rails : nil
    Object.const_set(:Rails, rails_mock)

    config = FlowChat::Intercom::Configuration.from_credentials

    assert_equal "rails_token", config.access_token
    assert_equal "rails_secret", config.client_secret
    assert_equal "rails_admin_id", config.admin_id
    assert_equal true, config.skip_signature_validation
    assert_equal true, config.valid?
  ensure
    # Restore original Rails constant
    Object.send(:remove_const, :Rails)
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
    ENV["INTERCOM_ACCESS_TOKEN"] = "env_token"
    ENV["INTERCOM_CLIENT_SECRET"] = "env_secret"
    ENV["INTERCOM_ADMIN_ID"] = "env_admin_id"
    ENV["INTERCOM_SKIP_SIGNATURE_VALIDATION"] = "true"

    config = FlowChat::Intercom::Configuration.from_credentials

    assert_equal "env_token", config.access_token
    assert_equal "env_secret", config.client_secret
    assert_equal "env_admin_id", config.admin_id
    assert_equal true, config.skip_signature_validation
    assert config.valid?
  ensure
    # Clean up environment variables
    ENV.delete("INTERCOM_ACCESS_TOKEN")
    ENV.delete("INTERCOM_CLIENT_SECRET")
    ENV.delete("INTERCOM_ADMIN_ID")
    ENV.delete("INTERCOM_SKIP_SIGNATURE_VALIDATION")

    # Restore Rails constant if it existed
    Object.const_set(:Rails, rails_backup) if rails_backup
  end
end

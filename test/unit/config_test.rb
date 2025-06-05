require "test_helper"

class ConfigTest < Minitest::Test
  def test_general_config_accessible
    assert_respond_to FlowChat::Config, :logger
    assert_respond_to FlowChat::Config, :cache

    # Should return default logger
    assert_kind_of Logger, FlowChat::Config.logger

    # Just verify it responds to cache method
    assert_respond_to FlowChat::Config, :cache
  end

  def test_ussd_config_object_accessible
    assert_respond_to FlowChat::Config, :ussd

    ussd_config = FlowChat::Config.ussd
    assert_kind_of FlowChat::Config::UssdConfig, ussd_config
  end

  def test_ussd_config_defaults
    ussd_config = FlowChat::Config.ussd

    # Pagination defaults
    assert_equal 140, ussd_config.pagination_page_size
    assert_equal "0", ussd_config.pagination_back_option
    assert_equal "Back", ussd_config.pagination_back_text
    assert_equal "#", ussd_config.pagination_next_option
    assert_equal "More", ussd_config.pagination_next_text

    # Resumable sessions defaults
    assert_equal false, ussd_config.resumable_sessions_enabled
    assert_equal true, ussd_config.resumable_sessions_global
    assert_equal 300, ussd_config.resumable_sessions_timeout_seconds
  end

  def test_ussd_config_setter_methods
    original_page_size = FlowChat::Config.ussd.pagination_page_size
    original_enabled = FlowChat::Config.ussd.resumable_sessions_enabled

    begin
      # Test setters work
      FlowChat::Config.ussd.pagination_page_size = 200
      FlowChat::Config.ussd.resumable_sessions_enabled = true

      assert_equal 200, FlowChat::Config.ussd.pagination_page_size
      assert_equal true, FlowChat::Config.ussd.resumable_sessions_enabled
    ensure
      # Restore original values
      FlowChat::Config.ussd.pagination_page_size = original_page_size
      FlowChat::Config.ussd.resumable_sessions_enabled = original_enabled
    end
  end

  def test_ussd_config_singleton_instance
    # Should return the same instance each time
    config1 = FlowChat::Config.ussd
    config2 = FlowChat::Config.ussd

    assert_same config1, config2
  end

  def test_config_separation
    # General config should not have USSD methods
    refute_respond_to FlowChat::Config, :pagination_page_size
    refute_respond_to FlowChat::Config, :resumable_sessions_enabled

    # USSD config should not have general methods
    refute_respond_to FlowChat::Config.ussd, :logger
    refute_respond_to FlowChat::Config.ussd, :cache
  end

  def test_whatsapp_config_object_accessible
    assert_respond_to FlowChat::Config, :whatsapp

    whatsapp_config = FlowChat::Config.whatsapp
    assert_kind_of FlowChat::Config::WhatsappConfig, whatsapp_config
  end

  def test_whatsapp_config_defaults
    whatsapp_config = FlowChat::Config.whatsapp

    assert_equal :inline, whatsapp_config.message_handling_mode
    assert_equal "WhatsappMessageJob", whatsapp_config.background_job_class
  end

  def test_whatsapp_config_setter_methods
    original_mode = FlowChat::Config.whatsapp.message_handling_mode
    original_job_class = FlowChat::Config.whatsapp.background_job_class

    begin
      # Test setters work
      FlowChat::Config.whatsapp.message_handling_mode = :background
      FlowChat::Config.whatsapp.background_job_class = "CustomJob"

      assert_equal :background, FlowChat::Config.whatsapp.message_handling_mode
      assert_equal "CustomJob", FlowChat::Config.whatsapp.background_job_class
    ensure
      # Restore original values
      FlowChat::Config.whatsapp.message_handling_mode = original_mode
      FlowChat::Config.whatsapp.background_job_class = original_job_class
    end
  end

  def test_whatsapp_mode_validation
    config = FlowChat::Config::WhatsappConfig.new

    # Valid modes should work
    config.message_handling_mode = :inline
    assert_equal :inline, config.message_handling_mode

    config.message_handling_mode = :background
    assert_equal :background, config.message_handling_mode

    config.message_handling_mode = :simulator
    assert_equal :simulator, config.message_handling_mode

    # String modes should be converted to symbols
    config.message_handling_mode = "inline"
    assert_equal :inline, config.message_handling_mode

    # Invalid modes should raise error
    error = assert_raises(ArgumentError) do
      config.message_handling_mode = :invalid_mode
    end
    assert_includes error.message, "Invalid message handling mode: invalid_mode"
    assert_includes error.message, "Valid modes: inline, background, simulator"
  end

  def test_whatsapp_mode_helper_methods
    config = FlowChat::Config::WhatsappConfig.new

    # Test inline mode
    config.message_handling_mode = :inline
    assert config.inline_mode?
    refute config.background_mode?
    refute config.simulator_mode?

    # Test background mode
    config.message_handling_mode = :background
    refute config.inline_mode?
    assert config.background_mode?
    refute config.simulator_mode?

    # Test simulator mode
    config.message_handling_mode = :simulator
    refute config.inline_mode?
    refute config.background_mode?
    assert config.simulator_mode?
  end

  def test_whatsapp_config_singleton_instance
    # Should return the same instance each time
    config1 = FlowChat::Config.whatsapp
    config2 = FlowChat::Config.whatsapp

    assert_same config1, config2
  end

  def test_whatsapp_config_separation
    # General config should not have WhatsApp methods
    refute_respond_to FlowChat::Config, :message_handling_mode
    refute_respond_to FlowChat::Config, :background_job_class

    # WhatsApp config should not have general methods
    refute_respond_to FlowChat::Config.whatsapp, :logger
    refute_respond_to FlowChat::Config.whatsapp, :cache

    # WhatsApp config should not have USSD methods
    refute_respond_to FlowChat::Config.whatsapp, :pagination_page_size
    refute_respond_to FlowChat::Config.whatsapp, :resumable_sessions_enabled
  end

  def test_combine_validation_error_with_message_default
    # Should default to true
    assert_equal true, FlowChat::Config.combine_validation_error_with_message
  end

  def test_combine_validation_error_with_message_can_be_changed
    original_setting = FlowChat::Config.combine_validation_error_with_message
    
    # Should be able to change the setting
    FlowChat::Config.combine_validation_error_with_message = false
    assert_equal false, FlowChat::Config.combine_validation_error_with_message

    FlowChat::Config.combine_validation_error_with_message = true
    assert_equal true, FlowChat::Config.combine_validation_error_with_message
  ensure
    FlowChat::Config.combine_validation_error_with_message = original_setting
  end
end

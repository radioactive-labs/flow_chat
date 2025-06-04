require "test_helper"

class ConfigTest < Minitest::Test
  def test_general_config_accessible
    assert_respond_to FlowChat::Config, :logger
    assert_respond_to FlowChat::Config, :cache

    # Should return default logger
    assert_kind_of Logger, FlowChat::Config.logger

    # Should return default cache (nil)
    assert_nil FlowChat::Config.cache
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
end

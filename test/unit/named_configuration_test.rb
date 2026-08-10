require "test_helper"

class NamedConfigurationTest < Minitest::Test
  def setup
    FlowChat::Whatsapp::Configuration.clear_all!
    FlowChat::Telegram::Configuration.clear_all!
  end

  def teardown
    FlowChat::Whatsapp::Configuration.clear_all!
    FlowChat::Telegram::Configuration.clear_all!
  end

  # The bug a shared @@configurations would have introduced: one merged registry
  # across every platform.
  def test_registries_are_per_class
    FlowChat::Whatsapp::Configuration.new(:shared_name)

    assert FlowChat::Whatsapp::Configuration.exists?(:shared_name)
    refute FlowChat::Telegram::Configuration.exists?(:shared_name)
  end

  def test_get_returns_the_registered_configuration
    config = FlowChat::Whatsapp::Configuration.new(:acme)

    assert_same config, FlowChat::Whatsapp::Configuration.get(:acme)
  end

  def test_get_raises_with_the_platform_label
    error = assert_raises(ArgumentError) { FlowChat::Whatsapp::Configuration.get(:missing) }
    assert_equal "WhatsApp configuration 'missing' not found", error.message

    error = assert_raises(ArgumentError) { FlowChat::Telegram::Configuration.get(:missing) }
    assert_equal "Telegram configuration 'missing' not found", error.message
  end

  def test_configuration_names_lists_only_that_platform
    FlowChat::Whatsapp::Configuration.new(:wa_one)
    FlowChat::Telegram::Configuration.new(:tg_one)

    assert_equal [:wa_one], FlowChat::Whatsapp::Configuration.configuration_names
    assert_equal [:tg_one], FlowChat::Telegram::Configuration.configuration_names
  end
end

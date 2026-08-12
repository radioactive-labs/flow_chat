require "test_helper"

class MessengerConfigurationTest < Minitest::Test
  def teardown
    FlowChat::Messenger::Configuration.clear_all!
  end

  def test_valid_requires_token_page_and_verify_token
    config = FlowChat::Messenger::Configuration.new(nil)
    refute config.valid?

    config.access_token = "tok"
    config.page_id = "page_1"
    refute config.valid?, "verify_token is still missing"

    config.verify_token = "verify"
    assert config.valid?
  end

  def test_messages_url_uses_the_page_id
    config = FlowChat::Messenger::Configuration.new(nil)
    config.page_id = "page_1"

    assert_equal "#{FlowChat::Config.messenger.api_base_url}/page_1/messages", config.messages_url
  end

  def test_from_credentials_reads_environment
    ENV["MESSENGER_ACCESS_TOKEN"] = "env_token"
    ENV["MESSENGER_PAGE_ID"] = "env_page"
    ENV["MESSENGER_VERIFY_TOKEN"] = "env_verify"
    ENV["MESSENGER_APP_SECRET"] = "env_secret"

    config = FlowChat::Messenger::Configuration.from_credentials

    assert_equal "env_token", config.access_token
    assert_equal "env_page", config.page_id
    assert_equal "env_secret", config.app_secret
    assert config.valid?
  ensure
    %w[MESSENGER_ACCESS_TOKEN MESSENGER_PAGE_ID MESSENGER_VERIFY_TOKEN MESSENGER_APP_SECRET].each { |k| ENV.delete(k) }
  end

  def test_registers_by_name
    config = FlowChat::Messenger::Configuration.new(:acme)

    assert_same config, FlowChat::Messenger::Configuration.get(:acme)
  end

  def test_account_id_returns_the_page_id
    config = FlowChat::Messenger::Configuration.new(nil)
    config.page_id = "page_1"

    assert_equal "page_1", config.account_id
  end

  # Messenger only handles `object: "page"`, which names the Page, so the id a
  # delivery names and the id a send goes to are the same one. Instagram's
  # differ, which is why the gateway asks for this rather than account_id.
  def test_webhook_account_id_is_the_page_id
    config = FlowChat::Messenger::Configuration.new(nil)
    config.page_id = "page_1"

    assert_equal "page_1", config.webhook_account_id
  end

  # A predicate should answer true or false. The bare && chain returned nil for
  # a missing first field, which also logged "Configuration valid: " with an
  # empty value. Intercom and Telegram already pin this; these did not.
  def test_valid_returns_a_boolean_not_nil
    config = FlowChat::Messenger::Configuration.new(nil)

    assert_equal false, config.valid?

    config.access_token = "tok"
    config.page_id = "page_1"
    config.verify_token = "verify"

    assert_equal true, config.valid?
  end
end

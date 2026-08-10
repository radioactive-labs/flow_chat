require "test_helper"

class InstagramConfigurationTest < Minitest::Test
  def teardown
    FlowChat::Instagram::Configuration.clear_all!
  end

  def test_valid_requires_token_page_and_verify_token
    config = FlowChat::Instagram::Configuration.new(nil)
    refute config.valid?

    config.access_token = "tok"
    config.page_id = "page_1"
    refute config.valid?, "verify_token is still missing"

    config.verify_token = "verify"
    assert config.valid?
  end

  def test_messages_url_uses_the_page_id
    config = FlowChat::Instagram::Configuration.new(nil)
    config.page_id = "page_1"

    assert_equal "#{FlowChat::Config.instagram.api_base_url}/page_1/messages", config.messages_url
  end

  def test_from_credentials_reads_environment
    ENV["INSTAGRAM_ACCESS_TOKEN"] = "env_token"
    ENV["INSTAGRAM_PAGE_ID"] = "env_page"
    ENV["INSTAGRAM_ACCOUNT_ID"] = "env_ig_account"
    ENV["INSTAGRAM_VERIFY_TOKEN"] = "env_verify"
    ENV["INSTAGRAM_APP_SECRET"] = "env_secret"

    config = FlowChat::Instagram::Configuration.from_credentials

    assert_equal "env_token", config.access_token
    assert_equal "env_page", config.page_id
    assert_equal "env_ig_account", config.instagram_account_id
    assert_equal "env_secret", config.app_secret
    assert config.valid?
  ensure
    %w[INSTAGRAM_ACCESS_TOKEN INSTAGRAM_PAGE_ID INSTAGRAM_ACCOUNT_ID INSTAGRAM_VERIFY_TOKEN INSTAGRAM_APP_SECRET].each { |k| ENV.delete(k) }
  end

  def test_registers_by_name
    config = FlowChat::Instagram::Configuration.new(:acme)

    assert_same config, FlowChat::Instagram::Configuration.get(:acme)
  end

  # On the Facebook Login integration path the webhook entry is keyed on the
  # linked Facebook Page, not the Instagram account, so that is what an
  # inbound event must be checked against. Deliberate, not a bug.
  def test_account_id_is_the_linked_page
    config = FlowChat::Instagram::Configuration.new(nil)
    config.page_id = "page_1"
    config.instagram_account_id = "ig_1"

    assert_equal "page_1", config.account_id
  end

  def test_limits_are_instagram_specific
    assert_equal 1000, FlowChat::Config.instagram.max_text_length
    assert_equal 13, FlowChat::Config.instagram.max_quick_replies
    assert_equal 10, FlowChat::Config.instagram.max_carousel_elements
    assert_equal 3, FlowChat::Config.instagram.max_buttons_per_element
  end
end

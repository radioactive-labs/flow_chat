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

  # Unlike account_id, this does not depend on login: both ids are accepted
  # regardless of which login path the app uses, since an inbound delivery's
  # entry.id is not confirmed to carry one or the other.
  def test_account_ids_includes_both_the_page_and_the_instagram_account
    config = FlowChat::Instagram::Configuration.new(nil)
    config.page_id = "page_1"
    config.instagram_account_id = "ig_1"
    config.login = :instagram

    assert_equal ["page_1", "ig_1"], config.account_ids
  end

  def test_account_ids_omits_a_blank_id
    config = FlowChat::Instagram::Configuration.new(nil)
    config.page_id = "page_1"

    assert_equal ["page_1"], config.account_ids
  end

  def test_limits_are_instagram_specific
    assert_equal 1000, FlowChat::Config.instagram.max_text_length
    assert_equal 13, FlowChat::Config.instagram.max_quick_replies
    assert_equal 10, FlowChat::Config.instagram.max_carousel_elements
    assert_equal 3, FlowChat::Config.instagram.max_buttons_per_element
  end

  def test_login_defaults_to_facebook
    config = FlowChat::Instagram::Configuration.new(nil)
    assert_equal :facebook, config.login
  end

  def test_login_rejects_an_unknown_value
    config = FlowChat::Instagram::Configuration.new(nil)
    assert_raises(ArgumentError) { config.login = :whatsapp }
    assert_equal :facebook, config.login, "a rejected assignment must not partially apply"
  end

  def test_login_rejects_nil
    config = FlowChat::Instagram::Configuration.new(nil)
    assert_raises(ArgumentError) { config.login = nil }
  end

  # Locks the exact literal values, not just their shape, since this path is
  # the one already in production use and must not move under a refactor.
  def test_facebook_login_path_is_byte_for_byte_unchanged
    config = FlowChat::Instagram::Configuration.new(nil)
    config.page_id = "page_1"
    config.instagram_account_id = "ig_1"

    assert_equal "https://graph.facebook.com/v23.0", config.api_base_url
    assert_equal "page_1", config.account_id
    assert_equal "https://graph.facebook.com/v23.0/page_1/messages", config.messages_url
    assert_equal "https://graph.facebook.com/v23.0/page_1/message_attachments", config.attachment_upload_url
  end

  def test_instagram_login_path_uses_the_instagram_host_and_account
    config = FlowChat::Instagram::Configuration.new(nil)
    config.login = :instagram
    config.page_id = "page_1"
    config.instagram_account_id = "ig_1"

    assert_equal "https://graph.instagram.com/v23.0", config.api_base_url
    assert_equal "ig_1", config.account_id
    assert_equal "https://graph.instagram.com/v23.0/ig_1/messages", config.messages_url
    assert_equal "https://graph.instagram.com/v23.0/ig_1/message_attachments", config.attachment_upload_url
  end

  def test_valid_on_facebook_login_path_still_requires_page_id_not_instagram_account_id
    config = FlowChat::Instagram::Configuration.new(nil)
    config.access_token = "tok"
    config.verify_token = "verify"
    config.instagram_account_id = "ig_1"
    refute config.valid?, "page_id is still missing"

    config.page_id = "page_1"
    assert config.valid?
  end

  def test_valid_on_instagram_login_path_requires_instagram_account_id_not_page_id
    config = FlowChat::Instagram::Configuration.new(nil)
    config.login = :instagram
    config.access_token = "tok"
    config.verify_token = "verify"
    config.page_id = "page_1"
    refute config.valid?, "instagram_account_id is still missing, and page_id must not substitute for it"

    config.instagram_account_id = "ig_1"
    assert config.valid?
  end

  def test_from_credentials_reads_login_from_environment
    ENV["INSTAGRAM_ACCESS_TOKEN"] = "env_token"
    ENV["INSTAGRAM_ACCOUNT_ID"] = "env_ig_account"
    ENV["INSTAGRAM_VERIFY_TOKEN"] = "env_verify"
    ENV["INSTAGRAM_LOGIN"] = "instagram"

    config = FlowChat::Instagram::Configuration.from_credentials

    assert_equal :instagram, config.login
    assert config.valid?
  ensure
    %w[INSTAGRAM_ACCESS_TOKEN INSTAGRAM_ACCOUNT_ID INSTAGRAM_VERIFY_TOKEN INSTAGRAM_LOGIN].each { |k| ENV.delete(k) }
  end

  def test_from_credentials_defaults_login_to_facebook_when_unset
    ENV["INSTAGRAM_ACCESS_TOKEN"] = "env_token"
    ENV["INSTAGRAM_PAGE_ID"] = "env_page"
    ENV["INSTAGRAM_VERIFY_TOKEN"] = "env_verify"

    config = FlowChat::Instagram::Configuration.from_credentials

    assert_equal :facebook, config.login
  ensure
    %w[INSTAGRAM_ACCESS_TOKEN INSTAGRAM_PAGE_ID INSTAGRAM_VERIFY_TOKEN].each { |k| ENV.delete(k) }
  end

  # A predicate should answer true or false. The bare && chain returned nil for
  # a missing first field, which also logged "Configuration valid: " with an
  # empty value. Intercom and Telegram already pin this; these did not.
  def test_valid_returns_a_boolean_not_nil
    config = FlowChat::Instagram::Configuration.new(nil)

    assert_equal false, config.valid?

    config.access_token = "tok"
    config.page_id = "page_1"
    config.verify_token = "verify"

    assert_equal true, config.valid?
  end
end

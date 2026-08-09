require "test_helper"

class SecurityTest < Minitest::Test
  def setup
    @original_secret = FlowChat::Config.simulator_secret
    FlowChat::Config.simulator_secret = "test_simulator_secret"
  end

  def teardown
    FlowChat::Config.simulator_secret = @original_secret
  end

  # ============================================================================
  # SECURE COMPARE
  # ============================================================================

  def test_secure_compare_equal_strings
    assert_equal true, FlowChat::Security.secure_compare("hello", "hello")
  end

  def test_secure_compare_different_strings
    assert_equal false, FlowChat::Security.secure_compare("hello", "world")
  end

  def test_secure_compare_different_lengths
    assert_equal false, FlowChat::Security.secure_compare("hello", "hi")
    assert_equal false, FlowChat::Security.secure_compare("hi", "hello")
  end

  def test_secure_compare_empty_strings
    assert FlowChat::Security.secure_compare("", "")
    refute FlowChat::Security.secure_compare("", "hello")
  end

  def test_secure_compare_nil
    assert FlowChat::Security.secure_compare(nil, "")
    refute FlowChat::Security.secure_compare(nil, "hello")
  end

  def test_secure_compare_hmac_signatures
    secret = "test_secret"
    signature1 = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), secret, "test_message")
    signature2 = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), secret, "test_message")
    signature3 = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), secret, "different_message")

    assert FlowChat::Security.secure_compare(signature1, signature2)
    refute FlowChat::Security.secure_compare(signature1, signature3)
  end

  # ============================================================================
  # SIMULATOR COOKIE
  # ============================================================================

  def test_simulator_cookie_round_trips
    assert FlowChat::Security.valid_simulator_cookie?(FlowChat::Security.simulator_cookie)
  end

  def test_simulator_cookie_rejects_blank_and_malformed_values
    refute FlowChat::Security.valid_simulator_cookie?(nil)
    refute FlowChat::Security.valid_simulator_cookie?("")
    refute FlowChat::Security.valid_simulator_cookie?("invalid_cookie")
    refute FlowChat::Security.valid_simulator_cookie?(":")
    refute FlowChat::Security.valid_simulator_cookie?("not_a_timestamp:signature")
  end

  def test_simulator_cookie_rejects_a_forged_signature
    refute FlowChat::Security.valid_simulator_cookie?("#{Time.now.to_i}:deadbeef")
  end

  def test_simulator_cookie_rejects_a_signature_for_another_timestamp
    signature = FlowChat::Security.simulator_signature(Time.now.to_i - 60)
    refute FlowChat::Security.valid_simulator_cookie?("#{Time.now.to_i}:#{signature}")
  end

  def test_simulator_cookie_expires
    stale = Time.now.to_i - FlowChat::Security::SIMULATOR_COOKIE_TTL - 1
    refute FlowChat::Security.valid_simulator_cookie?(FlowChat::Security.simulator_cookie(stale))
  end

  def test_simulator_cookie_rejects_a_future_timestamp
    future = Time.now.to_i + FlowChat::Security::SIMULATOR_COOKIE_TTL + 1
    refute FlowChat::Security.valid_simulator_cookie?(FlowChat::Security.simulator_cookie(future))
  end

  def test_simulator_cookie_requires_a_configured_secret
    cookie = FlowChat::Security.simulator_cookie

    FlowChat::Config.simulator_secret = nil
    refute FlowChat::Security.valid_simulator_cookie?(cookie)

    FlowChat::Config.simulator_secret = ""
    refute FlowChat::Security.valid_simulator_cookie?(cookie)
  end
end

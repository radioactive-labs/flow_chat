require "test_helper"

class CacheSessionStoreTest < Minitest::Test
  def setup
    @mock_cache = MockCache.new
  end

  def test_ussd_session_key_generation
    context = create_ussd_context("test_session_123", "+256700123456")
    store = FlowChat::Session::CacheSessionStore.new(context, @mock_cache)

    session_key = store.send(:session_key)
    expected_key = "flow_chat:session:ussd:test_session_123:+256700123456"

    assert_equal expected_key, session_key
  end

  def test_whatsapp_session_key_generation
    context = create_whatsapp_context("+256700123456")
    store = FlowChat::Session::CacheSessionStore.new(context, @mock_cache)

    session_key = store.send(:session_key)
    expected_key = "flow_chat:session:whatsapp:+256700123456"

    assert_equal expected_key, session_key
  end

  def test_ussd_session_ttl
    context = create_ussd_context("test_session_123", "+256700123456")
    store = FlowChat::Session::CacheSessionStore.new(context, @mock_cache)

    ttl = store.send(:session_ttl)
    expected_ttl = 1.hour

    assert_equal expected_ttl, ttl
  end

  def test_whatsapp_session_ttl
    context = create_whatsapp_context("+256700123456")
    store = FlowChat::Session::CacheSessionStore.new(context, @mock_cache)

    ttl = store.send(:session_ttl)
    expected_ttl = 7.days

    assert_equal expected_ttl, ttl
  end

  def test_get_returns_cached_value
    context = create_ussd_context("test_session_get", "+256700123456")
    store = FlowChat::Session::CacheSessionStore.new(context, @mock_cache)
    session_key = store.send(:session_key)

    # Pre-populate cache
    @mock_cache.write(session_key, {"name" => "John", "age" => 25})

    result = store.get("name")
    assert_equal "John", result
  end

  def test_get_returns_nil_for_missing_key
    context = create_ussd_context("test_session_missing", "+256700123456")
    store = FlowChat::Session::CacheSessionStore.new(context, @mock_cache)

    result = store.get("nonexistent")
    assert_nil result
  end

  def test_get_returns_nil_for_missing_session
    context = create_ussd_context("test_session_no_cache", "+256700123456")
    store = FlowChat::Session::CacheSessionStore.new(context, @mock_cache)

    result = store.get("name")
    assert_nil result
  end

  def test_set_stores_value_in_cache
    context = create_ussd_context("test_session_set", "+256700123456")
    store = FlowChat::Session::CacheSessionStore.new(context, @mock_cache)

    store.set("name", "Alice")

    # Verify value was stored
    session_key = store.send(:session_key)
    cached_data = @mock_cache.read(session_key)
    assert_equal "Alice", cached_data["name"]
  end

  def test_set_preserves_existing_values
    context = create_ussd_context("test_session_preserve", "+256700123456")
    store = FlowChat::Session::CacheSessionStore.new(context, @mock_cache)
    session_key = store.send(:session_key)

    # Pre-populate with some data
    @mock_cache.write(session_key, {"existing" => "value"})

    store.set("new_key", "new_value")

    # Verify both values exist
    cached_data = @mock_cache.read(session_key)
    assert_equal "value", cached_data["existing"]
    assert_equal "new_value", cached_data["new_key"]
  end

  def test_set_updates_ttl_on_write
    context = create_ussd_context("test_session_ttl", "+256700123456")
    store = FlowChat::Session::CacheSessionStore.new(context, @mock_cache)

    store.set("key", "value")

    # Verify TTL was set
    session_key = store.send(:session_key)
    assert @mock_cache.ttl_was_set?(session_key)
    assert_equal 1.hour, @mock_cache.last_ttl
  end

  def test_delete_removes_key_from_session
    context = create_ussd_context("test_session_delete", "+256700123456")
    store = FlowChat::Session::CacheSessionStore.new(context, @mock_cache)
    session_key = store.send(:session_key)

    # Pre-populate with data
    @mock_cache.write(session_key, {"keep" => "this", "delete" => "this"})

    store.delete("delete")

    # Verify only the specified key was deleted
    cached_data = @mock_cache.read(session_key)
    assert_equal "this", cached_data["keep"]
    refute cached_data.key?("delete")
  end

  def test_delete_handles_missing_session
    context = create_ussd_context("test_session_delete_missing", "+256700123456")
    store = FlowChat::Session::CacheSessionStore.new(context, @mock_cache)

    # Should not raise an error - just test that it doesn't crash
    store.delete("nonexistent")
    # If we get here, it didn't raise an error, which is what we want
    assert true
  end

  def test_clear_removes_entire_session
    context = create_whatsapp_context("+256700123456")
    store = FlowChat::Session::CacheSessionStore.new(context, @mock_cache)
    session_key = store.send(:session_key)

    # Pre-populate with data
    @mock_cache.write(session_key, {"name" => "John", "age" => 25})

    store.clear

    # Verify session was completely removed
    assert_nil @mock_cache.read(session_key)
  end

  def test_cross_platform_session_isolation
    ussd_context = create_ussd_context("shared_session", "+256700123456")
    whatsapp_context = create_whatsapp_context("+256700123456")

    ussd_store = FlowChat::Session::CacheSessionStore.new(ussd_context, @mock_cache)
    whatsapp_store = FlowChat::Session::CacheSessionStore.new(whatsapp_context, @mock_cache)

    # Set data in both sessions
    ussd_store.set("platform", "ussd")
    whatsapp_store.set("platform", "whatsapp")

    # Verify sessions are isolated
    assert_equal "ussd", ussd_store.get("platform")
    assert_equal "whatsapp", whatsapp_store.get("platform")
  end

  def test_different_users_session_isolation
    user1_context = create_whatsapp_context("+256700111111")
    user2_context = create_whatsapp_context("+256700222222")

    user1_store = FlowChat::Session::CacheSessionStore.new(user1_context, @mock_cache)
    user2_store = FlowChat::Session::CacheSessionStore.new(user2_context, @mock_cache)

    # Set data for both users
    user1_store.set("name", "User One")
    user2_store.set("name", "User Two")

    # Verify users have separate sessions
    assert_equal "User One", user1_store.get("name")
    assert_equal "User Two", user2_store.get("name")
    assert_nil user1_store.get("nonexistent")
  end

  def test_whatsapp_sessions_persist_longer
    whatsapp_context = create_whatsapp_context("+256700123456")
    ussd_context = create_ussd_context("test", "+256700123456")

    whatsapp_store = FlowChat::Session::CacheSessionStore.new(whatsapp_context, @mock_cache)
    ussd_store = FlowChat::Session::CacheSessionStore.new(ussd_context, @mock_cache)

    whatsapp_store.set("test", "whatsapp_value")
    ussd_store.set("test", "ussd_value")

    # Verify different TTLs were applied
    whatsapp_key = whatsapp_store.send(:session_key)
    ussd_key = ussd_store.send(:session_key)

    # Both should have had TTLs set, but with different values
    assert @mock_cache.ttl_was_set?(whatsapp_key)
    assert @mock_cache.ttl_was_set?(ussd_key)

    # The specific TTL values are tested in the individual ttl tests above
  end

  def test_handles_nil_context_gracefully
    store = FlowChat::Session::CacheSessionStore.new(nil, @mock_cache)

    # Should not crash with nil context
    assert_nil store.get("key")

    # Should not crash with nil context - just test that they don't raise errors
    store.set("key", "value")
    store.delete("key")
    store.clear
    # If we get here, none of them raised an error, which is what we want
    assert true
  end

  def test_handles_json_serialization_of_complex_data
    context = create_whatsapp_context("+256700123456")
    store = FlowChat::Session::CacheSessionStore.new(context, @mock_cache)

    complex_data = {
      "array" => [1, 2, 3],
      "hash" => {"nested" => "value"},
      "number" => 42,
      "boolean" => true,
      "string" => "text"
    }

    store.set("complex", complex_data)
    result = store.get("complex")

    assert_equal complex_data, result
  end

  def test_destroy_alias_works
    context = create_whatsapp_context("+256700123456")
    store = FlowChat::Session::CacheSessionStore.new(context, @mock_cache)
    session_key = store.send(:session_key)

    # Pre-populate with data
    @mock_cache.write(session_key, {"name" => "John"})

    store.destroy

    # Verify session was completely removed
    assert_nil @mock_cache.read(session_key)
  end

  def test_exists_method
    context = create_whatsapp_context("+256700123456")
    store = FlowChat::Session::CacheSessionStore.new(context, @mock_cache)
    store.send(:session_key)

    # Initially should not exist
    refute store.exists?

    # After setting data, should exist
    store.set("key", "value")
    assert store.exists?
  end

  def test_requires_cache_to_be_set
    context = create_whatsapp_context("+256700123456")

    # Should raise error when no cache is provided and Config.cache is nil
    original_cache = FlowChat::Config.cache
    FlowChat::Config.cache = nil

    error = assert_raises(ArgumentError) do
      FlowChat::Session::CacheSessionStore.new(context)
    end

    assert_equal "Cache is required. Set FlowChat::Config.cache or pass a cache instance.", error.message
  ensure
    # Restore original cache configuration
    FlowChat::Config.cache = original_cache
  end

  def test_uses_config_cache_as_default
    context = create_whatsapp_context("+256700123456")

    # Set a cache in config
    FlowChat::Config.cache = @mock_cache

    store = FlowChat::Session::CacheSessionStore.new(context)

    # Should use the configured cache
    store.set("test", "value")
    assert_equal "value", @mock_cache.read("flow_chat:session:whatsapp:+256700123456")["test"]
  ensure
    # Clean up
    FlowChat::Config.cache = nil
  end

  private

  def create_ussd_context(session_id, msisdn)
    context = FlowChat::Context.new
    context["request.id"] = session_id
    context["request.msisdn"] = msisdn
    context["request.gateway"] = :nalo
    context
  end

  def create_whatsapp_context(msisdn)
    context = FlowChat::Context.new
    context["request.msisdn"] = msisdn
    context["request.gateway"] = :whatsapp_cloud_api
    context
  end

  # Mock cache implementation for testing
  class MockCache
    def initialize
      @data = {}
      @ttls = {}
    end

    def read(key)
      @data[key]
    end

    def write(key, value, expires_in: nil)
      @data[key] = value
      @ttls[key] = expires_in if expires_in
      value
    end

    def delete(key)
      @data.delete(key)
      @ttls.delete(key)
    end

    def exist?(key)
      @data.key?(key)
    end

    def ttl_was_set?(key)
      @ttls.key?(key)
    end

    def last_ttl
      @ttls.values.last
    end
  end
end

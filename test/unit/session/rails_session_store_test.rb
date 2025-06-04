require "test_helper"

class RailsSessionStoreTest < Minitest::Test
  def setup
    @controller = mock_controller
    @controller.session[:flow_chat] = {}
    
    # Create a proper context like the middleware would
    @context = FlowChat::Context.new
    @context["controller"] = @controller
    @context["session.id"] = :flow_chat
    
    @store = FlowChat::Session::RailsSessionStore.new(@context)
  end

  def test_initializes_with_controller
    # Test that the store was initialized properly
    assert_equal :flow_chat, @store.instance_variable_get(:@session_id)
    assert_equal @controller.session, @store.instance_variable_get(:@session_store)
  end

  def test_get_returns_nil_for_missing_key
    assert_nil @store.get("nonexistent_key")
  end

  def test_set_and_get_string_key
    @store.set("test_key", "test_value")
    assert_equal "test_value", @store.get("test_key")
  end

  def test_set_and_get_symbol_key
    @store.set(:test_key, "test_value")
    assert_equal "test_value", @store.get(:test_key)
  end

  def test_set_and_get_mixed_keys
    @store.set("string_key", "string_value")
    @store.set(:symbol_key, "symbol_value")
    
    assert_equal "string_value", @store.get("string_key")
    assert_equal "symbol_value", @store.get(:symbol_key)
  end

  def test_stores_complex_objects
    complex_object = { name: "John", age: 25, hobbies: ["reading", "coding"] }
    @store.set(:user_data, complex_object)
    
    retrieved = @store.get(:user_data)
    # Since the store uses with_indifferent_access, keys become strings
    assert_equal "John", retrieved["name"]
    assert_equal 25, retrieved["age"]
    assert_equal ["reading", "coding"], retrieved["hobbies"]
  end

  def test_clear_removes_all_data
    @store.set(:key1, "value1")
    @store.set(:key2, "value2")
    @store.set(:key3, "value3")
    
    @store.destroy
    
    # After destroy, create a new store to verify data is gone
    new_store = FlowChat::Session::RailsSessionStore.new(@context)
    assert_nil new_store.get(:key1)
    assert_nil new_store.get(:key2)
    assert_nil new_store.get(:key3)
  end

  def test_destroy_doesnt_affect_other_session_data
    @controller.session[:other_data] = "should_remain"
    @store.set(:flow_data, "will_be_cleared")
    
    @store.destroy
    
    assert_equal "should_remain", @controller.session[:other_data]
    
    # Verify flow_chat data is cleared
    new_store = FlowChat::Session::RailsSessionStore.new(@context)
    assert_nil new_store.get(:flow_data)
  end

  def test_key_conversion_consistency
    # Test that string and symbol keys are handled consistently
    @store.set("test", "value1")
    @store.set(:test, "value2")
    
    # The last one should win, but both should access the same storage
    result1 = @store.get("test")
    result2 = @store.get(:test)
    
    assert_equal result1, result2
  end

  def test_namespaces_within_session
    # Ensure FlowChat data is properly namespaced
    @controller.session[:something_else] = "external_data"
    @store.set(:internal_key, "internal_data")
    
    assert_equal "external_data", @controller.session[:something_else]
    assert_equal "internal_data", @store.get(:internal_key)
    
    # FlowChat data should be under the :flow_chat key
    assert @controller.session[:flow_chat].is_a?(Hash)
  end

  def test_persistence_across_multiple_instances
    # First instance sets data
    store1 = FlowChat::Session::RailsSessionStore.new(@context)
    store1.set(:persistent_key, "persistent_value")
    
    # Second instance should see the same data
    store2 = FlowChat::Session::RailsSessionStore.new(@context)
    assert_equal "persistent_value", store2.get(:persistent_key)
  end
end 
require "test_helper"

class ContextTest < Minitest::Test
  def setup
    @context = FlowChat::Context.new
  end

  def test_acts_like_hash
    @context["key"] = "value"
    assert_equal "value", @context["key"]
  end

  def test_symbol_and_string_keys
    @context[:symbol_key] = "symbol_value"
    @context["string_key"] = "string_value"
    
    assert_equal "symbol_value", @context[:symbol_key]
    assert_equal "string_value", @context["string_key"]
  end

  def test_stores_complex_objects
    controller = mock_controller
    @context["controller"] = controller
    
    assert_equal controller, @context["controller"]
    assert_respond_to @context["controller"], :params
  end

  def test_responds_to_hash_methods
    assert_respond_to @context, :[]
    assert_respond_to @context, :[]=
  end
end 
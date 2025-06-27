require "test_helper"

class HttpAppTest < Minitest::Test
  def setup
    @context = FlowChat::Context.new
    @app = FlowChat::Http::App.new(@context)
  end

  def test_inherits_from_base_app
    assert_kind_of FlowChat::BaseApp, @app
  end

  def test_initializes_with_context
    assert_equal @context, @app.context
  end

  def test_responds_to_base_app_methods
    assert_respond_to @app, :say
    assert_respond_to @app, :screen
    assert_respond_to @app, :session
  end
end 
require "test_helper"

class HttpExecutorTest < Minitest::Test
  def setup
    @context = FlowChat::Context.new
    @mock_app = lambda { |ctx| [:prompt, "Test response", nil, nil] }
    @executor = FlowChat::Http::Middleware::Executor.new(@mock_app)
  end

  def test_inherits_from_base_executor
    assert_kind_of FlowChat::BaseExecutor, @executor
  end

  def test_platform_name
    assert_equal "HTTP", @executor.send(:platform_name)
  end

  def test_log_prefix
    assert_equal "Http::Executor", @executor.send(:log_prefix)
  end

  def test_build_platform_app
    app = @executor.send(:build_platform_app, @context)
    assert_kind_of FlowChat::Http::App, app
    assert_equal @context, app.context
  end

  def test_initializes_with_app
    assert_equal @mock_app, @executor.instance_variable_get(:@app)
  end
end

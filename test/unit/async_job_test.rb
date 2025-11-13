require "test_helper"

class AsyncJobTest < Minitest::Test
  class TestJob < FlowChat::AsyncJob
    attr_reader :received_controller, :received_job_params

    def execute(controller, **job_params)
      @received_controller = controller
      @received_job_params = job_params
    end
  end

  def test_perform_creates_background_controller_and_calls_execute
    request_data = {
      params: {"user_id" => "123", "input" => "Hello"},
      method: "POST",
      headers: {"Content-Type" => "application/json"}
    }

    job = TestJob.new
    job.perform(request_context: request_data)

    assert_instance_of FlowChat::BackgroundController, job.received_controller
    assert_equal "POST", job.received_controller.request.method
    assert_equal "123", job.received_controller.request.params["user_id"]
  end

  def test_async_job_raises_not_implemented_error_if_execute_not_overridden
    job = FlowChat::AsyncJob.new

    error = assert_raises(NotImplementedError) do
      job.perform(request_context: {})
    end

    assert_match(/execute/, error.message)
  end

  def test_perform_preserves_host_and_path_from_request_context
    request_data = {
      params: {"user_id" => "123"},
      method: "POST",
      headers: {},
      host: "example.com",
      path: "/webhooks/whatsapp"
    }

    job = TestJob.new
    job.perform(request_context: request_data)

    assert_equal "example.com", job.received_controller.request.host
    assert_equal "/webhooks/whatsapp", job.received_controller.request.path
  end

  def test_perform_passes_job_params_to_execute
    request_data = {
      params: {"user_id" => "123"},
      method: "POST",
      headers: {}
    }

    job = TestJob.new
    job.perform(request_context: request_data, deployment_id: 456, flow_name: "TestFlow")

    assert_equal 456, job.received_job_params[:deployment_id]
    assert_equal "TestFlow", job.received_job_params[:flow_name]
  end

  def test_perform_works_with_no_job_params
    request_data = {
      params: {"user_id" => "123"},
      method: "POST",
      headers: {}
    }

    job = TestJob.new
    job.perform(request_context: request_data)

    assert_equal({}, job.received_job_params)
  end
end

class BackgroundControllerTest < Minitest::Test
  def setup
    @request_data = {
      params: {"session_id" => "test_123", "input" => "Hello"},
      method: "POST",
      headers: {"Content-Type" => "application/json", "User-Agent" => "Test/1.0"}
    }
    @controller = FlowChat::BackgroundController.new(@request_data)
  end

  def test_initializes_with_background_request
    assert_instance_of FlowChat::BackgroundRequest, @controller.request
  end

  def test_render_is_noop_and_stores_response
    result = @controller.render(json: {status: "ok"})

    assert_nil result
    assert_equal({json: {status: "ok"}}, @controller.response)
  end

  def test_head_is_noop_and_stores_response
    result = @controller.head(:ok)

    assert_nil result
    assert_equal({status: :ok}, @controller.response)
  end

  def test_is_a_checks_for_background_controller
    assert @controller.is_a?(FlowChat::BackgroundController)
    assert @controller.kind_of?(FlowChat::BackgroundController)
  end

  def test_params_delegates_to_request_params
    # controller.params should delegate to request.params (Rails controller pattern)
    assert_equal @controller.params, @controller.request.params
    assert_equal "test_123", @controller.params[:session_id]
    assert_equal "Hello", @controller.params[:input]
  end
end

class BackgroundRequestTest < Minitest::Test
  def setup
    @request_data = {
      params: {"session_id" => "test_123", "input" => "Hello"},
      method: "POST",
      headers: {"Content-Type" => "application/json", "User-Agent" => "Test/1.0"}
    }
    @request = FlowChat::BackgroundRequest.new(@request_data)
  end

  def test_initializes_params_with_indifferent_access
    assert_equal "test_123", @request.params["session_id"]
    assert_equal "test_123", @request.params[:session_id]
  end

  def test_initializes_method
    assert_equal "POST", @request.method
  end

  def test_defaults_to_post_method
    request = FlowChat::BackgroundRequest.new({})
    assert_equal "POST", request.method
  end

  def test_initializes_headers_as_openstruct
    assert_equal "application/json", @request.headers["Content-Type"]
    assert_equal "Test/1.0", @request.headers["User-Agent"]
  end

  def test_post_predicate
    assert @request.post?

    get_request = FlowChat::BackgroundRequest.new(method: "GET")
    refute get_request.post?
  end

  def test_get_predicate
    refute @request.get?

    get_request = FlowChat::BackgroundRequest.new(method: "GET")
    assert get_request.get?
  end

  def test_body_returns_nil
    assert_nil @request.body
  end

  def test_cookies_returns_empty_hash
    assert_equal({}, @request.cookies)
  end

  def test_host_accessor
    request = FlowChat::BackgroundRequest.new(host: "example.com", path: "/test")
    assert_equal "example.com", request.host
  end

  def test_path_accessor
    request = FlowChat::BackgroundRequest.new(host: "example.com", path: "/webhooks/whatsapp")
    assert_equal "/webhooks/whatsapp", request.path
  end

  def test_host_and_path_default_to_nil
    request = FlowChat::BackgroundRequest.new({})
    assert_nil request.host
    assert_nil request.path
  end
end

require "test_helper"

class GatewayAsyncSupportTest < Minitest::Test
  class TestGateway
    include FlowChat::GatewayAsyncSupport

    def initialize(app)
      @app = app
    end
  end

  class NoAsyncGateway
    include FlowChat::GatewayAsyncSupport

    def initialize(app)
      @app = app
    end

    def async_supported?
      false
    end
  end

  def setup
    @app = proc { |context| [:text, "Response", nil, nil] }
    @gateway = TestGateway.new(@app)
    @context = FlowChat::Context.new
    @controller = create_mock_controller
  end

  def test_async_supported_defaults_to_true
    assert @gateway.async_supported?
  end

  def test_async_supported_can_be_overridden
    gateway = NoAsyncGateway.new(@app)
    refute gateway.async_supported?
  end

  def test_in_background_returns_false_for_normal_controller
    @gateway.instance_variable_set(:@controller, @controller)
    refute @gateway.in_background?
  end

  def test_in_background_returns_true_for_background_controller
    background_controller = FlowChat::BackgroundController.new({})
    @gateway.instance_variable_set(:@controller, background_controller)
    assert @gateway.in_background?
  end

  def test_should_enqueue_async_returns_false_when_no_processor
    @gateway.instance_variable_set(:@context, @context)
    @gateway.instance_variable_set(:@controller, @controller)

    refute @gateway.should_enqueue_async?
  end

  def test_should_enqueue_async_returns_false_when_processor_has_no_async
    processor = create_processor_without_async
    @context["processor"] = processor
    @gateway.instance_variable_set(:@context, @context)
    @gateway.instance_variable_set(:@controller, @controller)

    refute @gateway.should_enqueue_async?
  end

  def test_should_enqueue_async_returns_false_when_in_background
    processor = create_processor_with_async
    @context["processor"] = processor
    background_controller = FlowChat::BackgroundController.new({})
    @gateway.instance_variable_set(:@context, @context)
    @gateway.instance_variable_set(:@controller, background_controller)

    refute @gateway.should_enqueue_async?
  end

  def test_should_enqueue_async_returns_false_when_gateway_does_not_support_async
    processor = create_processor_with_async
    @context["processor"] = processor
    gateway = NoAsyncGateway.new(@app)
    gateway.instance_variable_set(:@context, @context)
    gateway.instance_variable_set(:@controller, @controller)

    refute gateway.should_enqueue_async?
  end

  def test_should_enqueue_async_returns_true_when_all_conditions_met
    processor = create_processor_with_async
    @context["processor"] = processor
    @gateway.instance_variable_set(:@context, @context)
    @gateway.instance_variable_set(:@controller, @controller)

    assert @gateway.should_enqueue_async?
  end

  def test_enqueue_async_job_returns_false_when_should_not_enqueue
    @gateway.instance_variable_set(:@context, @context)
    @gateway.instance_variable_set(:@controller, @controller)

    refute @gateway.enqueue_async_job
  end

  def test_enqueue_async_job_enqueues_job_when_should_enqueue
    job_class = Minitest::Mock.new
    job_class.expect(:perform_later, true) do |args|
      args[:request_context][:params].is_a?(Hash) &&
        args[:request_context][:method] == "POST"
    end

    # Create controller with proper params hash that supports to_unsafe_h
    controller = Object.new
    request = Object.new
    params_hash = {"input" => "test"}.with_indifferent_access
    request.define_singleton_method(:params) { params_hash }
    request.define_singleton_method(:method) { "POST" }
    request.define_singleton_method(:headers) { {"Content-Type" => "application/json"} }
    controller.define_singleton_method(:request) { request }
    controller.define_singleton_method(:is_a?) { |klass| klass == controller.class || super(klass) }

    processor = create_processor_with_async(job_class: job_class)
    @context["processor"] = processor
    @gateway.instance_variable_set(:@context, @context)
    @gateway.instance_variable_set(:@controller, controller)

    assert @gateway.enqueue_async_job
    job_class.verify
  end

  def test_extract_headers_for_background_extracts_common_headers
    request = Object.new
    request.define_singleton_method(:headers) do
      {
        "Content-Type" => "application/json",
        "User-Agent" => "Test/1.0",
        "X-Custom-Header" => "custom"
      }
    end

    extracted = @gateway.extract_headers_for_background(request)

    assert_equal "application/json", extracted["Content-Type"]
    assert_equal "Test/1.0", extracted["User-Agent"]
    refute extracted.key?("X-Custom-Header")
  end

  def test_extract_headers_for_background_handles_missing_headers
    request = Object.new
    request.define_singleton_method(:headers) { {} }

    extracted = @gateway.extract_headers_for_background(request)

    assert_equal({}, extracted)
  end

  def test_extract_host_returns_host_from_request
    request = Object.new
    request.define_singleton_method(:host) { "example.com" }

    assert_equal "example.com", @gateway.extract_host(request)
  end

  def test_extract_path_returns_path_from_request
    request = Object.new
    request.define_singleton_method(:path) { "/webhooks/whatsapp" }

    assert_equal "/webhooks/whatsapp", @gateway.extract_path(request)
  end

  def test_extract_host_returns_nil_on_error
    request = Object.new

    assert_nil @gateway.extract_host(request)
  end

  def test_extract_path_returns_nil_on_error
    request = Object.new

    assert_nil @gateway.extract_path(request)
  end

  def test_enqueue_async_job_serializes_host_and_path
    job_class = Minitest::Mock.new
    job_class.expect(:perform_later, true) do |args|
      args[:request_context][:host] == "example.com" &&
        args[:request_context][:path] == "/webhooks/whatsapp"
    end

    controller = Object.new
    request = Object.new
    params_hash = {"input" => "test"}.with_indifferent_access
    request.define_singleton_method(:params) { params_hash }
    request.define_singleton_method(:method) { "POST" }
    request.define_singleton_method(:headers) { {"Content-Type" => "application/json"} }
    request.define_singleton_method(:host) { "example.com" }
    request.define_singleton_method(:path) { "/webhooks/whatsapp" }
    controller.define_singleton_method(:request) { request }
    controller.define_singleton_method(:is_a?) { |klass| klass == controller.class || super(klass) }

    processor = create_processor_with_async(job_class: job_class)
    @context["processor"] = processor
    @gateway.instance_variable_set(:@context, @context)
    @gateway.instance_variable_set(:@controller, controller)

    assert @gateway.enqueue_async_job
    job_class.verify
  end

  private

  def create_mock_controller
    controller = Object.new
    request = Object.new

    request.define_singleton_method(:params) { {"input" => "test"}.with_indifferent_access }
    request.define_singleton_method(:method) { "POST" }
    request.define_singleton_method(:headers) { {"Content-Type" => "application/json", "User-Agent" => "Test/1.0"} }

    controller.define_singleton_method(:request) { request }
    controller.define_singleton_method(:is_a?) { |klass| klass == controller.class || super(klass) }

    controller
  end

  def create_processor_without_async
    processor = Object.new
    def processor.async_enabled?
      false
    end
    processor
  end

  def create_processor_with_async(job_class: nil, job_params: {})
    processor = Object.new
    def processor.async_enabled?
      true
    end
    processor.define_singleton_method(:async_job_class) { job_class }
    processor.define_singleton_method(:async_job_params) { job_params }
    processor
  end
end

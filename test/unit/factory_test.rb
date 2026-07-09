require "test_helper"

class FactoryTest < Minitest::Test
  def setup
    FlowChat::Factory.clear!
  end

  def teardown
    FlowChat::Factory.clear!
  end

  def test_register_factory
    FlowChat::Factory.register(:test) { |controller| }
    assert FlowChat::Factory.registered?(:test)
  end

  def test_registered_returns_false_for_unregistered_factory
    refute FlowChat::Factory.registered?(:unknown)
  end

  def test_execute_runs_factory_block
    executed = false
    FlowChat::Factory.register(:test) do |controller|
      executed = true
    end

    FlowChat::Factory.execute(:test, controller: mock_controller)
    assert executed
  end

  def test_execute_raises_when_not_registered
    error = assert_raises(FlowChat::Factory::FactoryNotFoundError) do
      FlowChat::Factory.execute(:unknown, controller: mock_controller)
    end
    assert_match(/not registered/, error.message)
    assert_match(/unknown/, error.message)
  end

  def test_clear_removes_all_factories
    FlowChat::Factory.register(:test) { |controller| }
    FlowChat::Factory.register(:test2) { |controller| }

    FlowChat::Factory.clear!

    refute FlowChat::Factory.registered?(:test)
    refute FlowChat::Factory.registered?(:test2)
  end

  def test_registered_factories_returns_all_names
    FlowChat::Factory.register(:whatsapp) { |controller| }
    FlowChat::Factory.register(:intercom) { |controller| }

    factories = FlowChat::Factory.registered_factories
    assert_equal [:whatsapp, :intercom].sort, factories.sort
  end

  def test_registered_factories_returns_empty_array_when_none_registered
    assert_equal [], FlowChat::Factory.registered_factories
  end

  def test_execute_passes_controller_to_block
    received_controller = nil

    FlowChat::Factory.register(:test) do |controller|
      received_controller = controller
    end

    test_controller = mock_controller

    FlowChat::Factory.execute(:test, controller: test_controller)

    assert_equal test_controller, received_controller
  end

  def test_register_overwrites_existing_factory
    first_executed = false
    second_executed = false

    FlowChat::Factory.register(:test) do |controller|
      first_executed = true
    end

    FlowChat::Factory.register(:test) do |controller|
      second_executed = true
    end

    FlowChat::Factory.execute(:test, controller: mock_controller)

    refute first_executed
    assert second_executed
  end

  def test_factory_can_access_controller_params
    received_params = nil

    FlowChat::Factory.register(:test) do |controller|
      received_params = controller.request.params
    end

    controller = mock_controller(params: {"user_id" => "123", "input" => "Hello"})
    FlowChat::Factory.execute(:test, controller: controller)

    assert_equal "123", received_params["user_id"]
    assert_equal "Hello", received_params["input"]
  end

  def test_factory_can_build_and_run_processor
    flow_executed = false

    test_flow = Class.new do
      def initialize(app)
        @app = app
      end

      define_method(:start) do
        flow_executed = true
        @app.say "Test"
      end

      def self.name
        "TestFlow"
      end
    end

    test_job = Class.new(FlowChat::AsyncJob) do
      def execute(controller, **job_params)
        # No-op
      end
    end

    FlowChat::Factory.register(:test) do |controller|
      processor = FlowChat::Processor.new(controller) do |config|
        config.use_gateway(TestGateway)
        config.use_session_store(MockSessionStore)
        config.use_async(test_job)
      end
      processor.run(test_flow, :start)
    end

    controller = mock_controller
    FlowChat::Factory.execute(:test, controller: controller)

    assert flow_executed
  end

  private

  def mock_controller(params: {})
    controller = Object.new
    request = Object.new

    default_params = {"input" => "test"}.merge(params).with_indifferent_access
    request.define_singleton_method(:params) { default_params }
    request.define_singleton_method(:method) { "POST" }
    request.define_singleton_method(:headers) { {"Content-Type" => "application/json"} }
    request.define_singleton_method(:post?) { true }

    controller.define_singleton_method(:request) { request }
    controller.define_singleton_method(:render) { |args| nil }
    controller.define_singleton_method(:head) { |status| nil }

    controller
  end

  class TestGateway
    def initialize(app)
      @app = app
    end

    def call(context)
      context["request.id"] = "test_123"
      context["request.platform"] = :test
      context["request.gateway"] = :test
      context.input = ""
      @app.call(context)
      context.controller.head :ok
    end
  end

  class MockSessionStore
    def initialize(session_options = nil)
      @options = session_options
    end

    def load(_session_id, _context)
      {}
    end

    def save(_session_id, _session_data, _context)
    end

    def destroy
      # No-op for mock
    end
  end
end

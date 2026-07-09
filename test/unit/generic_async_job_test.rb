require "test_helper"

class GenericAsyncJobTest < Minitest::Test
  def setup
    FlowChat::Factory.clear!
  end

  def teardown
    FlowChat::Factory.clear!
  end

  def test_execute_runs_registered_factory
    executed = false

    FlowChat::Factory.register(:test_factory) do |controller|
      executed = true
    end

    request_data = {
      params: {"user_id" => "123"},
      method: "POST",
      headers: {}
    }

    job = FlowChat::GenericAsyncJob.new
    job.perform(request_context: request_data, factory: :test_factory)

    assert executed
  end

  def test_execute_passes_controller_to_factory
    received_controller = nil

    FlowChat::Factory.register(:test_factory) do |controller|
      received_controller = controller
    end

    request_data = {
      params: {"user_id" => "123", "input" => "Hello"},
      method: "POST",
      headers: {}
    }

    job = FlowChat::GenericAsyncJob.new
    job.perform(request_context: request_data, factory: :test_factory)

    assert_instance_of FlowChat::BackgroundController, received_controller
    assert_equal "123", received_controller.params["user_id"]
    assert_equal "Hello", received_controller.params["input"]
  end

  def test_execute_raises_error_for_unregistered_factory
    request_data = {
      params: {"user_id" => "123"},
      method: "POST",
      headers: {}
    }

    job = FlowChat::GenericAsyncJob.new

    error = assert_raises(FlowChat::Factory::FactoryNotFoundError) do
      job.perform(request_context: request_data, factory: :unknown_factory)
    end

    assert_match /not registered/, error.message
    assert_match /unknown_factory/, error.message
  end

  def test_execute_ignores_extra_job_params
    executed = false

    FlowChat::Factory.register(:test_factory) do |controller|
      executed = true
    end

    request_data = {
      params: {"user_id" => "123"},
      method: "POST",
      headers: {}
    }

    job = FlowChat::GenericAsyncJob.new
    # Extra params are ignored by GenericAsyncJob but don't cause errors
    job.perform(request_context: request_data, factory: :test_factory, extra_param: "ignored")

    assert executed
  end
end

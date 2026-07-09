# frozen_string_literal: true

module FlowChat
  # Generic background job that uses the Factory pattern
  # Automatically used when use_async is called without a job class
  #
  # Example:
  #   # In webhook controller
  #   processor = FlowChat::Processor.new(self) do |config|
  #     config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
  #     config.use_session_store FlowChat::Session::CacheSessionStore
  #     config.use_async(factory: :whatsapp)  # No job class - uses GenericAsyncJob
  #   end
  #
  #   # Background job executes:
  #   FlowChat::Factory.execute(:whatsapp, controller: controller)
  class GenericAsyncJob < AsyncJob
    def execute(controller, factory:, **job_params)
      FlowChat.logger.debug { "GenericAsyncJob: Executing factory '#{factory}' with params: #{job_params.inspect}" }

      unless FlowChat::Factory.registered?(factory)
        raise FlowChat::Factory::FactoryNotFoundError, "Factory '#{factory}' not registered"
      end

      FlowChat::Factory.execute(factory, controller: controller)

      FlowChat.logger.debug { "GenericAsyncJob: Factory '#{factory}' executed successfully" }
    end
  end
end

# frozen_string_literal: true

module FlowChat
  # Factory provides centralized processor configuration for consistent setup across
  # webhook and background contexts.
  #
  # Example:
  #   # In config/initializers/flow_chat.rb
  #   FlowChat::Factory.register :whatsapp do |controller|
  #     processor = FlowChat::Processor.new(controller) do |config|
  #       config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
  #       config.use_session_store FlowChat::Session::CacheSessionStore
  #       config.use_session_config(boundaries: [:flow])
  #       config.use_async(WhatsAppFlowJob)
  #     end
  #     processor.run(WhatsAppFlow, :start)
  #   end
  #
  #   # In webhook controller
  #   FlowChat::Factory.execute(:whatsapp, controller: self)
  #
  #   # In background job
  #   FlowChat::Factory.execute(:whatsapp, controller: controller)
  class Factory
    class << self
      # Register a processor factory with a given name
      #
      # @param name [Symbol] The factory name (e.g., :whatsapp, :intercom)
      # @param block [Proc] The factory block that receives controller
      # @return [void]
      #
      # @example
      #   FlowChat::Factory.register :whatsapp do |controller|
      #     processor = FlowChat::Processor.new(controller) do |config|
      #       config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
      #     end
      #     processor.run(WhatsAppFlow, :start)
      #   end
      def register(name, &block)
        FlowChat.logger.debug { "Factory: Registering factory '#{name}'" }
        factories[name] = block
      end

      # Execute a registered factory
      #
      # @param name [Symbol] The factory name
      # @param controller [Object] The controller instance (webhook or background)
      # @return [void]
      # @raise [FactoryNotFoundError] If factory is not registered
      #
      # @example
      #   FlowChat::Factory.execute(:whatsapp, controller: self)
      def execute(name, controller:)
        factory = factories[name]
        raise FactoryNotFoundError, "Factory '#{name}' not registered" unless factory

        FlowChat.logger.debug { "Factory: Executing factory '#{name}'" }
        factory.call(controller)
      end

      # Check if a factory is registered
      #
      # @param name [Symbol] The factory name
      # @return [Boolean]
      def registered?(name)
        factories.key?(name)
      end

      # Get all registered factory names
      #
      # @return [Array<Symbol>]
      def registered_factories
        factories.keys
      end

      # Clear all registered factories (primarily for testing)
      #
      # @return [void]
      def clear!
        FlowChat.logger.debug { "Factory: Clearing all registered factories" }
        factories.clear
      end

      private

      def factories
        @factories ||= {}
      end
    end

    # Error raised when attempting to execute an unregistered factory
    class FactoryNotFoundError < StandardError; end
  end
end

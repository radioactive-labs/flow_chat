require "middleware"

module FlowChat
  class BaseProcessor
    attr_reader :middleware

    def initialize(controller, enable_simulator: nil)
      FlowChat.logger.debug { "BaseProcessor: Initializing processor for controller #{controller.class.name}" }
      
      @context = FlowChat::Context.new
      @context["controller"] = controller
      @context["enable_simulator"] = enable_simulator.nil? ? (defined?(Rails) && Rails.env.local?) : enable_simulator
      @middleware = ::Middleware::Builder.new(name: middleware_name)

      FlowChat.logger.debug { "BaseProcessor: Simulator mode #{@context["enable_simulator"] ? "enabled" : "disabled"}" }

      yield self if block_given?
      
      FlowChat.logger.info { "BaseProcessor: Initialized #{self.class.name} successfully" }
    end

    def use_gateway(gateway_class, *args)
      FlowChat.logger.debug { "BaseProcessor: Configuring gateway #{gateway_class.name} with args: #{args.inspect}" }
      @gateway_class = gateway_class
      @gateway_args = args
      self
    end

    def use_session_store(session_store)
      FlowChat.logger.debug { "BaseProcessor: Configuring session store #{session_store.class.name}" }
      @context["session.store"] = session_store
      self
    end

    def use_middleware(middleware)
      FlowChat.logger.debug { "BaseProcessor: Adding middleware #{middleware.class.name}" }
      @middleware.use middleware
      self
    end

    def run(flow_class, action)
      FlowChat.logger.info { "BaseProcessor: Starting flow execution - Flow: #{flow_class.name}, Action: #{action}" }
      
      @context["flow.name"] = flow_class.name.underscore
      @context["flow.class"] = flow_class
      @context["flow.action"] = action

      FlowChat.logger.debug { "BaseProcessor: Context prepared for flow #{flow_class.name}" }

      stack = build_middleware_stack
      yield stack if block_given?

      FlowChat.logger.debug { "BaseProcessor: Executing middleware stack for #{flow_class.name}##{action}" }
      result = stack.call(@context)
      
      FlowChat.logger.info { "BaseProcessor: Flow execution completed - Flow: #{flow_class.name}, Action: #{action}" }
      result
    rescue => error
      FlowChat.logger.error { "BaseProcessor: Flow execution failed - Flow: #{flow_class.name}, Action: #{action}, Error: #{error.class.name}: #{error.message}" }
      FlowChat.logger.debug { "BaseProcessor: Stack trace: #{error.backtrace.join("\n")}" }
      raise
    end

    protected

    # Subclasses should override these methods
    def middleware_name
      raise NotImplementedError, "Subclasses must implement middleware_name"
    end

    def build_middleware_stack
      raise NotImplementedError, "Subclasses must implement build_middleware_stack"
    end

    # Helper method for building stacks
    def create_middleware_stack(name)
      raise ArgumentError, "Gateway is required. Call use_gateway(gateway_class, *args) before running." unless @gateway_class

      ::Middleware::Builder.new(name: name) do |b|
        b.use @gateway_class, *@gateway_args
        configure_middleware_stack(b)
      end.inject_logger(FlowChat.logger)
    end

    def configure_middleware_stack(builder)
      raise NotImplementedError, "Subclasses must implement configure_middleware_stack"
    end
  end
end

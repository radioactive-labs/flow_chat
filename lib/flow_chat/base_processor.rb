require "middleware"

module FlowChat
  class BaseProcessor
    include FlowChat::Instrumentation

    attr_reader :middleware

    def initialize(controller, enable_simulator: nil)
      FlowChat.logger.debug { "BaseProcessor: Initializing processor for controller #{controller.class.name}" }

      @context = FlowChat::Context.new
      @context["controller"] = controller
      @context["enable_simulator"] = enable_simulator.nil? ? (defined?(Rails) && Rails.env.local?) : enable_simulator
      @middleware = ::Middleware::Builder.new(name: middleware_name)
      @session_options = FlowChat::Config.session

      FlowChat.logger.debug { "BaseProcessor: Simulator mode #{@context["enable_simulator"] ? "enabled" : "disabled"}" }

      yield self if block_given?

      FlowChat.logger.debug { "BaseProcessor: Initialized #{self.class.name} successfully" }
    end

    def use_gateway(gateway_class, *args)
      FlowChat.logger.debug { "BaseProcessor: Configuring gateway #{gateway_class.name} with args: #{args.inspect}" }
      @gateway_class = gateway_class
      @gateway_args = args
      self
    end

    def use_session_store(session_store)
      raise "Session store must be a class" unless session_store.is_a?(Class)
      FlowChat.logger.debug { "BaseProcessor: Configuring session store #{session_store.name}" }
      @context["session.store"] = session_store
      self
    end

    def use_session_config(boundaries: nil, hash_phone_numbers: nil, identifier: nil)
      FlowChat.logger.debug { "BaseProcessor: Configuring session config: boundaries=#{boundaries.inspect}, hash_phone_numbers=#{hash_phone_numbers}, identifier=#{identifier}" }
      
      # Update the session options directly
      @session_options = @session_options.dup
      @session_options.boundaries = Array(boundaries) if boundaries
      @session_options.hash_phone_numbers = hash_phone_numbers if hash_phone_numbers
      @session_options.identifier = identifier if identifier
      
      self
    end

    def use_middleware(middleware)
      raise "Middleware must be a class" unless middleware.is_a?(Class)
      FlowChat.logger.debug { "BaseProcessor: Adding middleware #{middleware.name}" }
      @middleware.use middleware
      self
    end

    def use_cross_platform_sessions
      FlowChat.logger.debug { "BaseProcessor: Enabling cross-platform sessions via session configuration" }
      use_session_config(
        boundaries: [:flow]
      )
      self
    end

    def run(flow_class, action)
      # Instrument flow execution (this will log via LogSubscriber)
      instrument(Events::FLOW_EXECUTION_START, {
        flow_name: flow_class.name.underscore,
        action: action.to_s,
        processor_type: self.class.name
      })

      @context["flow.name"] = flow_class.name.underscore
      @context["flow.class"] = flow_class
      @context["flow.action"] = action

      FlowChat.logger.debug { "BaseProcessor: Context prepared for flow #{flow_class.name}" }

      stack = build_middleware_stack
      yield stack if block_given?

      FlowChat.logger.debug { "BaseProcessor: Executing middleware stack for #{flow_class.name}##{action}" }

      # Instrument flow execution with timing (this will log completion via LogSubscriber)
      instrument(Events::FLOW_EXECUTION_END, {
        flow_name: flow_class.name.underscore,
        action: action.to_s,
        processor_type: self.class.name
      }) do
        stack.call(@context)
      end
    rescue => error
      FlowChat.logger.error { "BaseProcessor: Flow execution failed - #{flow_class.name}##{action}, Error: #{error.class.name}: #{error.message}" }
      FlowChat.logger.debug { "BaseProcessor: Stack trace: #{error.backtrace.join("\n")}" }

      # Instrument flow execution error (this will log error via LogSubscriber)
      instrument(Events::FLOW_EXECUTION_ERROR, {
        flow_name: flow_class.name.underscore,
        action: action.to_s,
        processor_type: self.class.name,
        error_class: error.class.name,
        error_message: error.message,
        backtrace: error.backtrace&.first(10)
      })

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
        b.use FlowChat::Session::Middleware, @session_options
        configure_middleware_stack(b)
      end.inject_logger(FlowChat.logger)
    end

    def configure_middleware_stack(builder)
      raise NotImplementedError, "Subclasses must implement configure_middleware_stack"
    end

    attr_reader :context
  end
end

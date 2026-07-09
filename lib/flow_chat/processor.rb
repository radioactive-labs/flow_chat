require "middleware"

module FlowChat
  class Processor
    include FlowChat::Instrumentation

    attr_reader :custom_middleware_builder, :context, :async_job_class, :async_job_params

    def initialize(controller, enable_simulator: nil)
      FlowChat.logger.debug { "Processor: Initializing processor for controller #{controller.class.name}" }

      @context = FlowChat::Context.new
      @context["controller"] = controller
      @context["enable_simulator"] = enable_simulator.nil? ? (defined?(Rails) && Rails.env.local?) : enable_simulator
      @custom_middleware_builder = ::Middleware::Builder.new(name: "processor.custom_middleware_builder")
      @session_options = FlowChat::Config.session
      @async_job_class = nil
      @async_job_params = {}

      FlowChat.logger.debug { "Processor: Simulator mode #{@context["enable_simulator"] ? "enabled" : "disabled"}" }

      yield self if block_given?

      FlowChat.logger.debug { "Processor: Initialized #{self.class.name} successfully" }
    end

    def use_gateway(gateway_class, *args)
      FlowChat.logger.debug { "Processor: Configuring gateway #{gateway_class.name} with args: #{args.inspect}" }
      @gateway_class = gateway_class
      @gateway_args = args
      self
    end

    def use_session_store(session_store)
      raise "Session store must be a class" unless session_store.is_a?(Class)
      FlowChat.logger.debug { "Processor: Configuring session store #{session_store.name}" }
      @context["session.store"] = session_store
      self
    end

    def use_session_config(boundaries: nil, hash_identifiers: nil, identifier: nil, &block)
      if block_given?
        FlowChat.logger.debug { "Processor: Configuring session config with custom proc" }
        @session_options = @session_options.dup
        @session_options.session_id_proc = block
      else
        FlowChat.logger.debug { "Processor: Configuring session config: boundaries=#{boundaries.inspect}, hash_identifiers=#{hash_identifiers}, identifier=#{identifier}" }

        # Update the session options directly
        @session_options = @session_options.dup
        @session_options.boundaries = Array(boundaries) unless boundaries.nil?
        @session_options.hash_identifiers = hash_identifiers unless hash_identifiers.nil?
        @session_options.identifier = identifier unless identifier.nil?
      end

      self
    end

    def use_middleware(middleware)
      if block_given?
        yield custom_middleware_builder
        return self
      end

      raise "Middleware must be a class" unless middleware.is_a?(Class)
      FlowChat.logger.debug { "Processor: Adding custom middleware: #{middleware.name}" }
      custom_middleware_builder.use middleware
      self
    end

    def use_cross_platform_sessions
      FlowChat.logger.debug { "Processor: Enabling cross-platform sessions via session configuration" }
      use_session_config(
        boundaries: [:flow]
      )
    end

    def use_url_isolation
      FlowChat.logger.debug { "Processor: Enabling URL-based session isolation" }
      current_boundaries = @session_options.boundaries.dup
      current_boundaries << :url unless current_boundaries.include?(:url)
      use_session_config(boundaries: current_boundaries)
    end

    def use_durable_sessions(cross_gateway: false)
      FlowChat.logger.debug { "Processor: Enabling durable sessions via session configuration" }
      use_session_config(
        identifier: :user_id
      )
    end

    def use_async(job_class = nil, **job_params)
      # If no job class provided, use GenericAsyncJob with factory param
      if job_class.nil?
        unless job_params.key?(:factory)
          raise ArgumentError, "When use_async is called without a job class, factory: parameter is required"
        end

        FlowChat.logger.debug { "Processor: Configuring async processing with GenericAsyncJob for factory '#{job_params[:factory]}'" }
        @async_job_class = FlowChat::GenericAsyncJob
      else
        FlowChat.logger.debug { "Processor: Configuring async processing with job class #{job_class.name} and params: #{job_params.inspect}" }
        @async_job_class = job_class
      end
      @async_job_params = job_params

      self
    end

    def async_enabled?
      !@async_job_class.nil?
    end

    def run(flow_class, action, **options)
      # Instrument flow execution (this will log via LogSubscriber)
      instrument(Events::FLOW_EXECUTION_START, {
        flow_name: flow_class.name.underscore,
        action: action.to_s,
        processor_type: self.class.name
      })

      @context["processor"] = self
      @context["flow.name"] = flow_class.name.underscore
      @context["flow.class"] = flow_class
      @context["flow.action"] = action
      @context["flow.options"] = options

      FlowChat.logger.debug { "Processor: Context prepared for flow #{flow_class.name}" }

      stack = create_middleware_stack
      yield stack if block_given?

      FlowChat.logger.debug { "Processor: Executing middleware stack for #{flow_class.name}##{action}" }

      # Instrument flow execution with timing (this will log completion via LogSubscriber)
      instrument(Events::FLOW_EXECUTION_END, {
        flow_name: flow_class.name.underscore,
        action: action.to_s
      }) do
        stack.call(@context)
      end
    rescue => error
      FlowChat.logger.error { "Processor: Flow execution failed - #{flow_class.name}##{action}, Error: #{error.class.name}: #{error.message}" }
      FlowChat.logger.debug { "Processor: Stack trace: #{error.backtrace.join("\n")}" }

      # Instrument flow execution error (this will log error via LogSubscriber)
      instrument(Events::FLOW_EXECUTION_ERROR, {
        flow_name: flow_class.name.underscore,
        action: action.to_s,
        error_class: error.class.name,
        error_message: error.message,
        backtrace: error.backtrace&.first(10)
      })

      raise
    end

    protected

    # Helper method for building stacks
    def create_middleware_stack
      raise ArgumentError, "Gateway is required. Call use_gateway(gateway_class, *args) before running." unless @gateway_class

      middleware_stack = ::Middleware::Builder.new(name: @gateway_class.name) do |b|
        # Gateway always comes first
        b.use @gateway_class, *@gateway_args
        # Session middleware next. We need to setup our session identifiers
        b.use FlowChat::Session::Middleware, @session_options

        if @gateway_class.respond_to?(:configure_middleware_stack)
          FlowChat.logger.debug { "Processor: Using platform specific middleware configuration" }
          @gateway_class.configure_middleware_stack(b, custom_middleware_builder)
        else
          b.use custom_middleware_builder
          FlowChat.logger.debug { "Processor: Added custom middleware" }
        end

        # Executor always goes last.
        # Nothing can execute after it.
        b.use FlowChat::Executor
      end

      middleware_stack.inject_logger(FlowChat.logger) if FlowChat::Config.inject_middleware_logger

      middleware_stack
    end
  end
end

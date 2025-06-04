require "middleware"

module FlowChat
  class BaseProcessor
    attr_reader :middleware

    def initialize(controller)
      @context = FlowChat::Context.new
      @context["controller"] = controller
      @middleware = ::Middleware::Builder.new(name: middleware_name)

      yield self if block_given?
    end

    def use_gateway(gateway_class, *args)
      @gateway_class = gateway_class
      @gateway_args = args
      self
    end

    def use_session_store(session_store)
      @context["session.store"] = session_store
      self
    end

    def use_middleware(middleware)
      @middleware.use middleware
      self
    end

    def run(flow_class, action)
      @context["flow.name"] = flow_class.name.underscore
      @context["flow.class"] = flow_class
      @context["flow.action"] = action

      stack = build_middleware_stack
      yield stack if block_given?

      stack.call(@context)
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
      end.inject_logger(Rails.logger)
    end

    def configure_middleware_stack(builder)
      raise NotImplementedError, "Subclasses must implement configure_middleware_stack"
    end
  end
end

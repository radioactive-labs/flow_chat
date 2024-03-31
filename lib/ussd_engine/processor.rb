require "middleware"

module UssdEngine
  class Processor
    class Interrupt < Exception
      attr_reader :prompt

      def initialize(prompt)
        @prompt = prompt
        super
      end
    end

    class Prompt < Interrupt
      attr_reader :choices

      def initialize(*args, choices: nil)
        @choices = choices
        super(*args)
      end
    end

    class Terminate < Interrupt; end

    attr_reader :middleware, :gateway

    def initialize(controller)
      @context = UssdEngine::Context.new
      @context["controller"] = controller
      @middleware = ::Middleware::Builder.new(name: "ussd_engine.middleware")

      yield self if block_given?
    end

    def use_gateway(gateway)
      @gateway = gateway
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

    def use_resumable_sessions
      middleware.insert_before 0, UssdEngine::Middleware::ResumableSession
      self
    end

    def use_pagination
      middleware.use UssdEngine::Middleware::Pagination
    end

    def run(action)
      @context["request.action"] = action

      ::Middleware::Builder.new name: "ussd_engine" do |b|
        b.use gateway
        b.use UssdEngine::Middleware::Session
        # b.use UssdEngine::Middleware::Pagination
        b.use middleware
        b.use UssdEngine::Middleware::Executor
      end.inject_logger(Rails.logger).call(@context)
    end
  end
end

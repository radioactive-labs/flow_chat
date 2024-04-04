require "middleware"

module FlowChat
  module Ussd
    class Processor
      attr_reader :middleware, :gateway

      def initialize(controller)
        @context = FlowChat::Context.new
        @context["controller"] = controller
        @middleware = ::Middleware::Builder.new(name: "ussd.middleware")

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
        middleware.insert_before 0, FlowChat::Ussd::Middleware::ResumableSession
        self
      end

      def use_pagination
        middleware.use FlowChat::Ussd::Middleware::Pagination
      end

      def run(flow, action)
        @context["flow.class"] = flow
        @context["flow.action"] = action

        ::Middleware::Builder.new name: "ussd" do |b|
          b.use gateway
          b.use FlowChat::Session::Middleware
          # b.use FlowChat::Middleware::Pagination
          b.use middleware
          b.use FlowChat::Ussd::Middleware::Executor
        end.inject_logger(Rails.logger).call(@context)
      end
    end
  end
end

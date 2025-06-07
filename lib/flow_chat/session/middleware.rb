module FlowChat
  module Session
    class Middleware
      include FlowChat::Instrumentation

      attr_reader :context

      def initialize(app)
        @app = app
        FlowChat.logger.debug { "Session::Middleware: Initialized session middleware" }
      end

      def call(context)
        @context = context
        session_id = session_id(context)
        FlowChat.logger.debug { "Session::Middleware: Generated session ID: #{session_id}" }

        context["session.id"] = session_id
        context.session = context["session.store"].new(context)

        # Use instrumentation instead of direct logging for session creation
        instrument(Events::SESSION_CREATED, {
          session_id: session_id,
          store_type: context["session.store"].name,
          gateway: context["request.gateway"]
        })

        FlowChat.logger.debug { "Session::Middleware: Session store: #{context["session.store"].class.name}" }

        result = @app.call(context)

        FlowChat.logger.debug { "Session::Middleware: Session processing completed for #{session_id}" }
        result
      rescue => error
        FlowChat.logger.error { "Session::Middleware: Error in session processing for #{session_id}: #{error.class.name}: #{error.message}" }
        raise
      end

      private

      def session_id(context)
        gateway = context["request.gateway"]
        flow_name = context["flow.name"]

        FlowChat.logger.debug { "Session::Middleware: Building session ID for gateway=#{gateway}, flow=#{flow_name}" }

        case gateway
        when :whatsapp_cloud_api
          # For WhatsApp, use phone number + flow name for consistent sessions
          phone = context["request.msisdn"]
          session_id = "#{gateway}:#{flow_name}:#{phone}"
          FlowChat.logger.debug { "Session::Middleware: WhatsApp session ID created for phone #{phone}" }
          session_id
        # when :nalo, :nsano
        #   # For USSD, use the request ID from the gateway
        #   "#{gateway}:#{flow_name}:#{context["request.id"]}"
        else
          # Fallback to request ID
          request_id = context["request.id"]
          session_id = "#{gateway}:#{flow_name}:#{request_id}"
          FlowChat.logger.debug { "Session::Middleware: Generic session ID created for request #{request_id}" }
          session_id
        end
      end
    end
  end
end

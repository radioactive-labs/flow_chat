module FlowChat
  module Session
    class Middleware
      def initialize(app)
        @app = app
      end

      def call(context)
        context["session.id"] = session_id context
        context.session = context["session.store"].new(context)
        @app.call(context)
      end

      private

      def session_id(context)
        gateway = context["request.gateway"]
        flow_name = context["flow.name"]
        case gateway
        when :whatsapp_cloud_api
          # For WhatsApp, use phone number + flow name for consistent sessions
          phone = context["request.msisdn"]
          "#{gateway}:#{flow_name}:#{phone}"
        # when :nalo, :nsano
        #   # For USSD, use the request ID from the gateway
        #   "#{gateway}:#{flow_name}:#{context["request.id"]}"
        else
          # Fallback to request ID
          "#{gateway}:#{flow_name}:#{context["request.id"]}"
        end
      end
    end
  end
end

require "phonelib"

module FlowChat
  module Ussd
    module Gateway
      class Nsano
        include FlowChat::Instrumentation

        attr_reader :context

        def initialize(app)
          @app = app
        end

        def call(context)
          @context = context
          controller = context["controller"]
          controller.request

          # Add timestamp for all requests
          context["request.timestamp"] = Time.current.iso8601

          # Set a basic message_id (can be enhanced based on actual Nsano implementation)
          context["request.message_id"] = SecureRandom.uuid
          context["request.platform"] = :ussd

          # TODO: Implement Nsano-specific parameter parsing
          # For now, add basic instrumentation structure for when this is implemented

          # Placeholder instrumentation - indicates Nsano implementation is needed
          instrument(Events::MESSAGE_RECEIVED, {
            from: "TODO",  # Would be parsed from Nsano params
            message: "TODO",  # Would be actual user input
            session_id: "TODO",  # Would be Nsano session ID
            gateway: :nsano,
            platform: :ussd,
            timestamp: context["request.timestamp"]
          })

          # Process request with placeholder app call
          _, _, _, _ = @app.call(context) if @app

          # Placeholder response instrumentation
          instrument(Events::MESSAGE_SENT, {
            to: "TODO",  # Would be actual phone number
            session_id: "TODO",  # Would be Nsano session ID
            message: "TODO",  # Would be actual response message
            message_type: "prompt",  # Would depend on actual response type
            gateway: :nsano,
            platform: :ussd,
            content_length: 0,  # Would be actual content length
            timestamp: context["request.timestamp"]
          })

          # input = context["rack.input"].read
          # context["rack.input"].rewind
          # if input.present?
          #   params = JSON.parse input
          #   if params["network"].present? && params["UserSessionID"].present?
          #     request_id = "nsano::request_id::#{params["UserSessionID"]}"
          #     context["ussd.request"] = {
          #       gateway: :nsano,
          #       network: params["network"].to_sym,
          #       msisdn: Phonelib.parse(params["msisdn"]).e164,
          #       type: Config.cache&.read(request_id).present? ? :response : :initial,
          #       input: params["msg"].presence,
          #       network: params["network"]
          #     }
          #   end
          # end

          # status, headers, response = @app.call(context)

          # if context["ussd.response"].present? && context["ussd.request"][:gateway] == :nsano
          #   if context["ussd.response"][:type] == :terminal
          #     Config.cache&.write(request_id, nil)
          #   else
          #     Config.cache&.write(request_id, 1)
          #   end

          #   status = 200
          #   response =
          #     {
          #       USSDResp: {
          #         action: (context["ussd.response"][:type] == :terminal) ? :prompt : :input,
          #         menus: "",
          #         title: context["ussd.response"][:body]
          #       }
          #     }.to_json
          #   headers = headers.merge({"Content-Type" => "application/json", "Content-Length" => response.bytesize.to_s})
          #   response = [response]
          # end
          # [status, headers, response]
        end
      end
    end
  end
end

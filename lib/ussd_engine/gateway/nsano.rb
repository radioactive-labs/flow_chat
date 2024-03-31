require "phonelib"

module UssdEngine
  module Gateway
    class Nsano
      def initialize(app)
        @app = app
      end

      def call(context)
        controller = context["controller"]
        request = controller.request

        # input = context["rack.input"].read
        # context["rack.input"].rewind
        # if input.present?
        #   params = JSON.parse input
        #   if params["network"].present? && params["UserSessionID"].present?
        #     request_id = "nsano::request_id::#{params["UserSessionID"]}"
        #     context["ussd_engine.request"] = {
        #       provider: :nsano,
        #       network: params["network"].to_sym,
        #       msisdn: Phonelib.parse(params["msisdn"]).e164,
        #       type: Config.cache&.read(request_id).present? ? :response : :initial,
        #       input: params["msg"].presence,
        #       network: params["network"]
        #     }
        #   end
        # end

        # status, headers, response = @app.call(context)

        # if context["ussd_engine.response"].present? && context["ussd_engine.request"][:provider] == :nsano
        #   if context["ussd_engine.response"][:type] == :terminal
        #     Config.cache&.write(request_id, nil)
        #   else
        #     Config.cache&.write(request_id, 1)
        #   end

        #   status = 200
        #   response =
        #     {
        #       USSDResp: {
        #         action: (context["ussd_engine.response"][:type] == :terminal) ? :prompt : :input,
        #         menus: "",
        #         title: context["ussd_engine.response"][:body]
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

require "phonelib"

module UssdEngine
  module Middleware
    class NsanoProcessor
      def initialize(app)
        @app = app
      end

      def call(env)
        input = env["rack.input"].read
        env["rack.input"].rewind
        if input.present?
          params = JSON.parse input
          if params["network"].present? && params["UserSessionID"].present?
            request_id = "nsano::request_id::#{params["UserSessionID"]}"
            env["ussd_engine.request"] = {
              provider: :nsano,
              network: params["network"].to_sym,
              msisdn: Phonelib.parse(params["msisdn"]).e164,
              type: Config.cache&.read(request_id).present? ? :response : :initial,
              input: params["msg"].presence,
            }
          end
        end

        status, headers, response = @app.call(env)

        if env["ussd_engine.response"].present? && env["ussd_engine.request"][:provider] == :nsano
          if env["ussd_engine.response"][:type] == :terminal
            Config.cache&.write(request_id, nil)
          else
            Config.cache&.write(request_id, 1)
          end

          status = 200
          response =
            {
              USSDResp: {
                action: env["ussd_engine.response"][:type] == :terminal ? :prompt : :input,
                menus: "",
                title: env["ussd_engine.response"][:body],
              },
            }.to_json
          headers = headers.merge({ "Content-Type" => "application/json", "Content-Length" => response.bytesize.to_s })
          response = [response]
        end
        [status, headers, response]
      end
    end
  end
end

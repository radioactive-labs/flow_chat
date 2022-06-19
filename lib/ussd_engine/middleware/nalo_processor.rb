module UssdEngine
  module Middleware
    class NaloProcessor
      def initialize(app)
        @app = app
      end

      def call(env)
        input = env["rack.input"].read
        if input.present?
          params = JSON.parse input
          if params["USERID"].present? && params["MSISDN"].present?
            env["ussd_engine.request"] = {
              provider: :nalo,
              msisdn: params["MSISDN"],
              type: params["MSGTYPE"] ? :initial : :response,
              input: params["USERDATA"].presence,
            }
          end
        end

        status, headers, response = @app.call(env)

        if env["ussd_engine.response"].present? && env["ussd_engine.request"][:provider] == :nalo
          status = 200
          response =
            {
              USERID: params["USERID"],
              MSISDN: env["ussd_engine.request"][:msisdn],
              MSG: env["ussd_engine.response"][:body],
              MSGTYPE: env["ussd_engine.response"][:type] != :terminal,
            }.to_json
          headers = headers.merge({ "Content-Type" => "application/json", "Content-Length" => response.bytesize.to_s })
          response = [response]
        end
        [status, headers, response]
      end
    end
  end
end

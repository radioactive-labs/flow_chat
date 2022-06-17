module UssdEngine
  module Middleware
    class NaloProcessor
      def initialize(app)
        @app = app
      end

      def call(env)
        request = Rack::Request.new(env)
        env["ussd_engine.request"] = {
          provider: :nalo,
          msisdn: request.params["MSISDN"],
          type: request.params["MSGTYPE"] ? :initial : :response,
          input: request.params["USERDATA"],
        }

        status, headers, response = @app.call(env)

        if (env["ussd_engine.response"].present?)
          status = 200
          response =
            {
              USERID: request.params[:USERID],
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

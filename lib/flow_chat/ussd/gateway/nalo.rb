require "phonelib"

module FlowChat
  module Ussd
    module Gateway
      class Nalo
        def initialize(app)
          @app = app
        end

        def call(context)
          params = context.controller.request.params

          context["request.id"] = params["USERID"]
          context["request.gateway"] = :nalo
          context["request.network"] = nil
          context["request.msisdn"] = Phonelib.parse(params["MSISDN"]).e164
          # context["request.type"] = params["MSGTYPE"] ? :initial : :response
          context.input = params["USERDATA"].presence

          type, prompt, choices = @app.call(context)

          context.controller.render json: {
            USERID: params["USERID"],
            MSISDN: params["MSISDN"],
            MSG: render_prompt(prompt, choices),
            MSGTYPE: type == :prompt
          }
        end

        private

        def render_prompt(prompt, choices)
          FlowChat::Ussd::Renderer.new(prompt, choices).render
        end
      end
    end
  end
end

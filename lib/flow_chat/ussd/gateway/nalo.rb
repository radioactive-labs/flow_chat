require "phonelib"

module FlowChat
  module Ussd
    module Gateway
      class Nalo
        include FlowChat::Instrumentation
        
        
        attr_reader :context
        
        def initialize(app)
          @app = app
        end

        def call(context)
          @context = context
          params = context.controller.request.params

          context["request.id"] = params["USERID"]
          context["request.message_id"] = SecureRandom.uuid
          context["request.timestamp"] = Time.current.iso8601
          context["request.gateway"] = :nalo
          context["request.network"] = nil
          context["request.msisdn"] = Phonelib.parse(params["MSISDN"]).e164
          # context["request.type"] = params["MSGTYPE"] ? :initial : :response
          context.input = params["USERDATA"].presence

          # Instrument message received when user provides input using new scalable approach
          if context.input.present?
            instrument(Events::MESSAGE_RECEIVED, {
              from: context["request.msisdn"],
              message: context.input,
              session_id: context["request.id"],
              gateway: :nalo,
              platform: :ussd,
              timestamp: context["request.timestamp"]
            })
          end

          # Process the request and instrument the response
          type, prompt, choices, media = @app.call(context)
          
          # Instrument message sent using new scalable approach
          instrument(Events::MESSAGE_SENT, {
            to: context["request.msisdn"],
            session_id: context["request.id"],
            message: context.input || "",
            message_type: type == :prompt ? "prompt" : "terminal",
            gateway: :nalo,
            platform: :ussd,
            content_length: prompt.to_s.length,
            timestamp: context["request.timestamp"]
          })

          context.controller.render json: {
            USERID: params["USERID"],
            MSISDN: params["MSISDN"],
            MSG: render_prompt(prompt, choices, media),
            MSGTYPE: type == :prompt
          }
        end

        private

        def render_prompt(prompt, choices, media)
          FlowChat::Ussd::Renderer.new(prompt, choices: choices, media: media).render
        end
      end
    end
  end
end

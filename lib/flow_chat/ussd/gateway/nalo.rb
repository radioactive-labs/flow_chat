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
          context["request.msisdn"] = FlowChat::PhoneNumberUtil.to_e164(params["MSISDN"])
          context["request.user_id"] = context["request.msisdn"]
          context["request.message_id"] = SecureRandom.uuid
          context["request.timestamp"] = Time.current.iso8601
          context["request.gateway"] = :nalo
          context["request.platform"] = :ussd
          context["request.network"] = nil
          # context["request.type"] = params["MSGTYPE"] ? :initial : :response
          context.input = params["USERDATA"].presence || ""

          # Instrument message received when user provides input using new scalable approach
          if context.input.present?
            instrument(Events::MESSAGE_RECEIVED, {
              from: context["request.user_id"],
              message: context.input,
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
            message_type: (type == :prompt) ? "prompt" : "terminal",
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

        def self.configure_middleware_stack(builder, custom_middleware)
          FlowChat.logger.debug { "FlowChat::Ussd::Gateway::Nalo: Configuring middleware stack" }

          builder.use FlowChat::Ussd::Middleware::Pagination
          FlowChat.logger.debug { "FlowChat::Ussd::Gateway::Nalo: Added Ussd::Middleware::Pagination" }

          builder.use custom_middleware
          FlowChat.logger.debug { "FlowChat::Ussd::Gateway::Nalo: Added custom middleware" }

          builder.use FlowChat::Ussd::Middleware::ChoiceMapper
          FlowChat.logger.debug { "FlowChat::Ussd::Gateway::Nalo: Added Ussd::Middleware::ChoiceMapper" }
        end

        private

        def render_prompt(prompt, choices, media)
          FlowChat::Ussd::Renderer.new(prompt, choices: choices, media: media).render
        end
      end
    end
  end
end

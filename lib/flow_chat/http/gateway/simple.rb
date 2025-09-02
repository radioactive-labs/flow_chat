module FlowChat
  module Http
    module Gateway
      class Simple
        include FlowChat::Instrumentation

        attr_reader :context

        def initialize(app)
          @app = app
        end

        def call(context)
          @context = context
          params = context.controller.request.params
          request = context.controller.request

          # Validate request method
          unless request.get? || request.post?
            context.controller.head :bad_request
            return
          end

          # Extract basic request information
          context["request.id"] = params["session_id"] || SecureRandom.uuid
          context["request.msisdn"] = FlowChat::PhoneNumberUtil.to_e164(params["msisdn"])
          context["request.user_id"] = params["user_id"] || context["request.msisdn"] || context["request.id"]
          context["request.message_id"] = params["message_id"] || SecureRandom.uuid
          context["request.timestamp"] = Time.current.iso8601
          context["request.gateway"] = :http_simple
          context["request.platform"] = :http
          context["request.network"] = nil
          context["request.method"] = request.method
          context["request.path"] = request.path
          context["request.user_agent"] = request.user_agent
          context.input = params["input"].presence

          # Instrument message received when user provides input
          if context.input.present?
            instrument(Events::MESSAGE_RECEIVED, {
              from: context["request.user_id"],
              message: context.input,
              timestamp: context["request.timestamp"]
            })
          end

          # Process the request
          type, prompt, choices, media = @app.call(context)

          # Instrument message sent
          instrument(Events::MESSAGE_SENT, {
            to: context["request.user_id"],
            session_id: context["request.id"],
            message: context.input || "",
            message_type: (type == :prompt) ? "prompt" : "terminal",
            gateway: :http_simple,
            platform: :http,
            content_length: prompt.to_s.length,
            timestamp: context["request.timestamp"]
          })

          # Render response as JSON
          response_data = render_response(type, prompt, choices, media)
          context.controller.render json: response_data
        end

        private

        def render_response(type, prompt, choices, media)
          rendered = FlowChat::Http::Renderer.new(prompt, choices: choices, media: media).render

          {
            type: type,
            session_id: context["request.id"],
            user_id: context["request.user_id"],
            timestamp: context["request.timestamp"],
            **rendered
          }
        end
      end
    end
  end
end

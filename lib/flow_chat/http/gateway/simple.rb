module FlowChat
  module Http
    class ConfigurationError < StandardError; end

    module Gateway
      class Simple
        include FlowChat::Instrumentation
        include FlowChat::GatewayAsyncSupport

        attr_reader :context

        def initialize(app, user_params)
          @app = app
          @user_params = user_params

          validate_user_params!
        end

        def call(context)
          @context = context
          @controller = context.controller
          params = @controller.request.params
          request = @controller.request

          # Validate request method
          unless request.get? || request.post?
            @controller.head :bad_request
            return
          end

          # Set request information from user_params
          context["request.id"] = @user_params[:session_id]
          context["request.user_id"] = @user_params[:user_id]
          context["request.msisdn"] = @user_params[:msisdn] if @user_params[:msisdn]
          context["request.email"] = @user_params[:email] if @user_params[:email]
          context["request.message_id"] = SecureRandom.uuid
          context["request.timestamp"] = Time.current.iso8601
          context["request.gateway"] = :http_simple
          context["request.platform"] = :http
          context["request.body"] = (params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h).transform_keys(&:to_s)

          # HTTP-specific request metadata
          context["http.method"] = request.method
          context["http.path"] = request.path
          context["http.user_agent"] = request.user_agent
          context.input = params["input"].presence || ""

          # Instrument message received when user provides input
          if context.input.present?
            instrument(Events::MESSAGE_RECEIVED, {
              from: context["request.user_id"],
              message: context.input,
              timestamp: context["request.timestamp"]
            })
          end

          # Determine routing: async enqueue, background execute, or inline
          if should_enqueue_async?
            # HTTP request with async enabled → enqueue job and return immediately
            enqueue_async_job
            return @controller.render json: {status: "processing"}
          else
            # Background OR inline → process message
            # Process the request
            response = @app.call(context)

            # Handle nil response (e.g., from middleware that handles the response itself)
            unless response
              return @controller.render json: {
                type: :skip,
                session_id: context["request.id"],
                user_id: context["request.user_id"],
                timestamp: context["request.timestamp"]
              }
            end

            type, prompt, choices, media = response

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
            @controller.render json: response_data
          end
        end

        private

        def validate_user_params!
          required_keys = [:session_id, :user_id]

          required_keys.each do |key|
            unless @user_params.key?(key)
              raise FlowChat::Http::ConfigurationError,
                "HTTP Simple gateway requires :#{key} in user_params"
            end
          end
        end

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

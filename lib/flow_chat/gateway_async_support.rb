require_relative "async_job"

module FlowChat
  # Concern for gateways to support async background processing
  # Mix this into gateway classes to enable async detection and job enqueueing
  module GatewayAsyncSupport
    attr_reader :controller, :context

    # Check if gateway supports async processing
    # Override in gateways that don't support async (e.g., USSD)
    def async_supported?
      true
    end

    # Detect if we're currently in background mode
    def in_background?
      @controller.is_a?(::FlowChat::BackgroundController)
    end

    # Whether an earlier pass already announced this delivery's side events,
    # which is the case only for a job the gem enqueued after publishing them
    # itself. Being in the background is not enough on its own: an application
    # may build a request context and enqueue a job with no foreground pass
    # ahead of it, and then this pass is the first to see the delivery.
    #
    # in_background? short-circuits because a foreground controller is a Rails
    # controller, which knows nothing about side events.
    def side_events_already_published?
      in_background? && @controller.side_events_published?
    end

    # Check if async processing should be used
    # Returns true if:
    # - Not already in background mode
    # - Processor has async enabled
    # - Gateway supports async
    def should_enqueue_async?
      processor = @context["processor"]

      !in_background? &&
        processor&.async_enabled? &&
        async_supported?
    end

    # Enqueue background job with serialized request context
    # Returns true if job was enqueued, false otherwise
    def enqueue_async_job
      return false unless should_enqueue_async?

      processor = @context["processor"]

      FlowChat.logger.info { "#{self.class.name}: Async enabled - enqueuing background job" }

      # Serialize request data for BackgroundController
      #
      # side_events_published records that this pass has already announced the
      # delivery's side events, so the job it is about to enqueue does not
      # announce them a second time. It rides in the request context rather
      # than in params, where a platform's own webhook fields live.
      request_data = {
        params: @controller.request.params.to_h,
        method: @controller.request.method,
        headers: extract_headers_for_background(@controller.request),
        host: extract_host(@controller.request),
        path: extract_path(@controller.request),
        body: extract_body_for_background(@controller.request),
        remote_ip: extract_remote_ip(@controller.request),
        side_events_published: true
      }

      # Enqueue user's job with request context and job params
      processor.async_job_class.perform_later(
        request_context: request_data,
        **processor.async_job_params
      )

      FlowChat.logger.info { "#{self.class.name}: Background job enqueued successfully" }

      true
    end

    # Extract serializable headers needed for background processing
    # Override in gateways that need additional headers
    def extract_headers_for_background(request)
      {
        "Content-Type" => request.headers["Content-Type"],
        "User-Agent" => request.headers["User-Agent"]
      }.compact
    end

    # Extract host from request for URL boundary support
    def extract_host(request)
      request.host
    rescue
      nil
    end

    # Extract path from request for URL boundary support
    def extract_path(request)
      request.path
    rescue
      nil
    end

    # Extract request body for background processing
    # Override in gateways that need the request body
    def extract_body_for_background(request)
      return nil unless request.body

      body_content = request.body.read
      request.body.rewind  # Reset for subsequent reads
      body_content
    rescue
      nil
    end

    # Extract remote IP from request
    def extract_remote_ip(request)
      request.remote_ip
    rescue
      nil
    end
  end
end

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
      request_data = {
        params: @controller.request.params.to_h,
        method: @controller.request.method,
        headers: extract_headers_for_background(@controller.request),
        host: extract_host(@controller.request),
        path: extract_path(@controller.request)
      }

      # Enqueue user's job with request context
      processor.async_job_class.perform_later(
        request_context: request_data
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
  end
end

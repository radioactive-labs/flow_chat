require "active_support/notifications"

module FlowChat
  module Instrumentation
    extend ActiveSupport::Concern

    # Instrument a block of code with the given event name and payload
    def instrument(event_name, payload = {}, &block)
      enriched_payload = payload&.dup || {}
      if respond_to?(:context) && context
        enriched_payload[:request_id] = context["request.id"] if context["request.id"]
        enriched_payload[:session_id] = context["session.id"] if context["session.id"]
        enriched_payload[:flow_name] = context["flow.name"] if context["flow.name"]
        enriched_payload[:gateway] = context["request.gateway"] if context["request.gateway"]
        enriched_payload[:platform] = context["request.platform"] if context["request.platform"]
      end

      self.class.instrument(event_name, enriched_payload, &block)
    end

    # True when this turn carries something to process — text OR a structured
    # attachment (media/location/contact). Gateways gate MESSAGE_RECEIVED on this
    # so caption-less media, locations, and contacts are still instrumented: they
    # set a blank input string (not the old "$media$"-style sentinel), so a plain
    # `context.input.present?` check would silently drop them.
    def inbound_message?(context)
      return false unless context

      context.input.present? ||
        !context["request.media"].nil? ||
        !context["request.location"].nil? ||
        !context["request.contact"].nil?
    end

    class_methods do
      def instrument(event_name, payload = {}, &block)
        FlowChat::Instrumentation.instrument(event_name, payload, &block)
      end
    end

    # Module-level method for direct calls like FlowChat::Instrumentation.instrument
    def self.instrument(event_name, payload = {}, &block)
      full_event_name = "#{event_name}.flow_chat"

      enriched_payload = {
        timestamp: Time.current
      }.merge(payload || {}).compact

      ActiveSupport::Notifications.instrument(full_event_name, enriched_payload, &block)
    end

    # Shared helper for reporting API errors with instrumentation and Rails.error
    # @param message [String] Error message
    # @param error [Exception, nil] Original exception if available
    # @param context [Hash] Platform-specific error context (must include :platform)
    def self.report_api_error(message, error: nil, **context)
      error_context = context.compact

      # Instrument for custom subscribers
      instrument(Events::API_ERROR, error_context.merge(message: message))

      # Report to Rails.error if available
      if defined?(Rails) && Rails.respond_to?(:error) && Rails.error.respond_to?(:report)
        exception = error || StandardError.new(message)
        Rails.error.report(exception, handled: true, context: error_context)
      end
    end

    # Predefined event names for consistency
    module Events
      # Core framework events
      FLOW_EXECUTION_START = "flow.execution.start"
      FLOW_EXECUTION_END = "flow.execution.end"
      FLOW_EXECUTION_ERROR = "flow.execution.error"

      # Context events
      CONTEXT_CREATED = "context.created"

      # Session events
      SESSION_CREATED = "session.created"
      SESSION_DESTROYED = "session.destroyed"
      SESSION_DATA_GET = "session.data.get"
      SESSION_DATA_SET = "session.data.set"
      SESSION_CACHE_HIT = "session.cache.hit"
      SESSION_CACHE_MISS = "session.cache.miss"

      # Platform-agnostic messaging events
      # Gateway/platform information is included in the payload
      MESSAGE_RECEIVED = "message.received"
      MESSAGE_SENT = "message.sent"
      WEBHOOK_VERIFIED = "webhook.verified"
      WEBHOOK_FAILED = "webhook.failed"
      API_REQUEST = "api.request"
      MEDIA_UPLOAD = "media.upload"
      API_ERROR = "api.error"

      PAGINATION_TRIGGERED = "pagination.triggered"

      # Middleware events
      MIDDLEWARE_BEFORE = "middleware.before"
      MIDDLEWARE_AFTER = "middleware.after"

      # Conversation management events (for Intercom and similar platforms)
      CONVERSATION_ASSIGNED = "conversation.assigned"
      CONVERSATION_TAGGED = "conversation.tagged"
      CONVERSATION_STATE_CHANGED = "conversation.state_changed"
    end
  end
end

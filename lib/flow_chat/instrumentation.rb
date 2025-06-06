require "active_support/notifications"

module FlowChat
  module Instrumentation
    extend ActiveSupport::Concern

    # Instrument a block of code with the given event name and payload
    def instrument(event_name, payload = {}, &block)
      enriched_payload = payload&.dup || {}
      if respond_to?(:context) && context
        enriched_payload[:session_id] = context["session.id"] if context["session.id"]
        enriched_payload[:flow_name] = context["flow.name"] if context["flow.name"]
        enriched_payload[:gateway] = context["request.gateway"] if context["request.gateway"]
      end

      self.class.instrument(event_name, enriched_payload, &block)
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

    # Predefined event names for consistency
    module Events
      # Core framework events
      FLOW_EXECUTION_START = "flow.execution.start"
      FLOW_EXECUTION_END = "flow.execution.end"
      FLOW_EXECUTION_ERROR = "flow.execution.error"
      
      # Session events
      SESSION_CREATED = "session.created"
      SESSION_DESTROYED = "session.destroyed"
      SESSION_DATA_GET = "session.data.get"
      SESSION_DATA_SET = "session.data.set"
      SESSION_CACHE_HIT = "session.cache.hit"
      SESSION_CACHE_MISS = "session.cache.miss"
      
      # WhatsApp events
      WHATSAPP_MESSAGE_RECEIVED = "whatsapp.message.received"
      WHATSAPP_MESSAGE_SENT = "whatsapp.message.sent"
      WHATSAPP_WEBHOOK_VERIFIED = "whatsapp.webhook.verified"
      WHATSAPP_WEBHOOK_FAILED = "whatsapp.webhook.failed"
      WHATSAPP_API_REQUEST = "whatsapp.api.request"
      WHATSAPP_MEDIA_UPLOAD = "whatsapp.media.upload"
      
      # USSD events
      USSD_MESSAGE_RECEIVED = "ussd.message.received"
      USSD_MESSAGE_SENT = "ussd.message.sent"
      USSD_PAGINATION_TRIGGERED = "ussd.pagination.triggered"
      
      # Middleware events
      MIDDLEWARE_BEFORE = "middleware.before"
      MIDDLEWARE_AFTER = "middleware.after"
      
      # Context events
      CONTEXT_CREATED = "context.created"
    end
  end
end 
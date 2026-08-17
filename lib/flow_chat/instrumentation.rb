require "active_support/notifications"

module FlowChat
  module Instrumentation
    extend ActiveSupport::Concern

    # Where a delivered reply's platform message id is left on the context, the
    # same way for every gateway. nil when the platform does not name one.
    DELIVERED_MESSAGE_ID_KEY = "delivery.platform_message_id"

    # How long the send itself took, in milliseconds, left here by
    # report_delivery_failure for the gateway to put on MESSAGE_SENT.
    #
    # Measured rather than taken from ActiveSupport::Notifications' own event
    # duration: a block event is published whatever the block returns, so
    # timing the send that way meant publishing MESSAGE_SENT for sends that
    # failed. The event is emitted after the fact instead, which leaves its
    # own duration at zero, so the real figure is carried in the payload.
    DELIVERY_DURATION_KEY = "delivery.duration_ms"

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

    # Wraps a delivery so a reply the platform would not take is reported.
    #
    # A gateway sends after the middleware stack has returned. An app that
    # records what the flow said has therefore already recorded it, and
    # recorded it as having gone out, before anything knows whether it did.
    # The send is the only place that learns otherwise, and it is downstream of
    # everything that could act on it.
    #
    # Reported two ways, because two different kinds of reader want it.
    #
    # The event is a broadcast, and takes the same shape its gateway gives
    # MESSAGE_SENT: what was being sent and where, and nothing else. Anyone may
    # subscribe, including tools that write whatever they are handed straight
    # into a log, so it carries no more than the send itself already announces.
    #
    # The callback is the app that owns this turn, acting on records only it
    # knows about. It gets the whole context because it is the app's own code,
    # configured by the app, and reading what the app put there. That is not
    # true of a subscriber, and the context holds the gateway client and the
    # raw inbound body.
    #
    # Re-raises whatever the send raised: this reports a failure, it does not
    # handle one.
    # A send fails two ways and only one of them raises. Every client here answers
    # with the platform's parsed response when the message was accepted and nil
    # once it has already logged an API error, so a nil result is a failure that
    # arrived quietly. Treating it as success fired on_delivery_success for a
    # message that was never delivered, and stamped a nil id onto the context as
    # though the platform had named one.
    #
    # It reports rather than raises, because the client already decided not to:
    # turning a swallowed API error into an exception here would fail the webhook
    # for a reply the platform merely declined.
    def report_delivery_failure(context, **payload)
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = yield
      context[DELIVERY_DURATION_KEY] = elapsed_ms_since(started_at)

      if result.nil?
        error = FlowChat::DeliveryError.new("#{payload[:platform] || "the platform"} did not accept the message")
        report_to_subscribers(error, payload)
        report_to_app(context, error)
        return nil
      end

      report_delivery_success(context, result)
      result
    rescue => error
      context[DELIVERY_DURATION_KEY] ||= elapsed_ms_since(started_at) if started_at
      report_to_subscribers(error, payload)
      report_to_app(context, error)
      raise error
    end

    def elapsed_ms_since(started_at)
      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(2)
    end

    # The success half. Runs where the send happened, which is the only place that
    # knows what the platform called the message.
    def report_delivery_success(context, result)
      context[DELIVERED_MESSAGE_ID_KEY] = platform_message_id_from(result)
      FlowChat::Config.on_delivery_success&.call(context, result)
    rescue => callback_error
      FlowChat.logger.error do
        "Instrumentation: on_delivery_success raised #{callback_error.class}: #{callback_error.message}"
      end
    end

    # What the platform called the message it just accepted.
    #
    # Overridden by every gateway that delivers out of band, because each one is
    # the only thing that knows the shape of its own client's answer. Naming it
    # here rather than in each app is the point: an app stamping the id onto its
    # own record should not have to carry a case statement over platforms.
    def platform_message_id_from(result)
      nil
    end

    # Neither reader may replace the delivery error with one of its own, which
    # would hide the failure they are being told about. Notifications gather
    # subscriber errors and re-raise them, so both are reachable.
    def report_to_subscribers(error, payload)
      instrument(Events::MESSAGE_DELIVERY_FAILED, payload.merge(
        error_class: error.class.name,
        message: error.message
      ))
    rescue => subscriber_error
      FlowChat.logger.error do
        "Instrumentation: a #{Events::MESSAGE_DELIVERY_FAILED} subscriber raised " \
          "#{subscriber_error.class}: #{subscriber_error.message}"
      end
    end

    def report_to_app(context, error)
      FlowChat::Config.on_delivery_failure&.call(context, error)
    rescue => callback_error
      FlowChat.logger.error do
        "Instrumentation: on_delivery_failure raised #{callback_error.class}: #{callback_error.message}"
      end
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
    #
    # `message` is prose for a human reading logs. Subscribers deciding what to
    # do about an error should read the structured keys instead, so that
    # rewording a message never changes behaviour somewhere else:
    #
    #   error_class  the exception's class, filled in here from `error`
    #   error_type   what kind of failure it is, named by the adapter
    #   error_code   the platform's own code, where it gives one
    #
    # @param message [String] Human readable description, for logs
    # @param error [Exception, nil] Original exception if available
    # @param context [Hash] Platform-specific error context (must include :platform)
    def self.report_api_error(message, error: nil, **context)
      error_context = context.compact

      # An exception's class is a classification the caller already made. Carry
      # it so a subscriber can branch on it rather than parsing the message.
      error_context[:error_class] ||= error.class.name if error

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
      # A reply the flow produced that the platform would not take. Carries
      # what its gateway gives MESSAGE_SENT, plus the error, so a subscriber
      # sees the same send it would have seen succeed.
      MESSAGE_DELIVERY_FAILED = "message.delivery_failed"
      # A platform's own report of what became of a message we sent. Informational:
      # the send already succeeded or failed at the API call.
      MESSAGE_STATUS = "message.status"
      WEBHOOK_VERIFIED = "webhook.verified"
      WEBHOOK_FAILED = "webhook.failed"
      API_REQUEST = "api.request"
      MEDIA_UPLOAD = "media.upload"
      API_ERROR = "api.error"

      PAGINATION_TRIGGERED = "pagination.triggered"

      # Middleware events
      MIDDLEWARE_BEFORE = "middleware.before"
      MIDDLEWARE_AFTER = "middleware.after"

      # A webhook this gateway verified but does not model, handed on whole.
      #
      # FlowChat's job is messaging: inbound turns, the replies they produce, and
      # what became of them. A platform sends far more than that, and what an
      # account ban, a contact sync or an imported history means belongs to the
      # application, not here. Rather than grow a handler per field, the payload is
      # published with the field that named it, for an application to dispatch on.
      WEBHOOK_RECEIVED = "webhook.received"

      # Conversation management events (for Intercom and similar platforms)
      CONVERSATION_ASSIGNED = "conversation.assigned"
      CONVERSATION_TAGGED = "conversation.tagged"
      CONVERSATION_STATE_CHANGED = "conversation.state_changed"
    end
  end
end

module FlowChat
  module Instrumentation
    module Setup
      class << self
        attr_accessor :log_subscriber, :metrics_collector

        # Initialize instrumentation with default subscribers
        def initialize!
          setup_log_subscriber if FlowChat::Config.logger
          setup_metrics_collector

          FlowChat.logger&.info { "FlowChat::Instrumentation: Initialized with logging and metrics collection" }
        end

        # Set up both logging and metrics collection
        def setup_instrumentation!(options = {})
          setup_logging!(options)
          setup_metrics!(options)
        end

        # Set up logging (LogSubscriber)
        def setup_logging!(options = {})
          return if @log_subscriber_setup

          require_relative "log_subscriber"
          setup_log_subscriber(options)
          @log_subscriber_setup = true
        end

        # Set up metrics collection (MetricsCollector)
        def setup_metrics!(options = {})
          return if @metrics_collector_setup

          require_relative "metrics_collector"
          setup_metrics_collector(options)
          @metrics_collector_setup = true
        end

        # Cleanup all subscribers
        def cleanup!
          @log_subscriber = nil
          @metrics_collector = nil

          # Note: ActiveSupport::Notifications doesn't provide an easy way to
          # unsubscribe all subscribers, so this is mainly for reference cleanup
          FlowChat.logger&.info { "FlowChat::Instrumentation: Cleaned up instrumentation" }
        end

        # Get current metrics (thread-safe)
        def metrics
          @metrics_collector&.snapshot || {}
        end

        # Reset metrics
        def reset_metrics!
          @metrics_collector&.reset!
        end

        # Subscribe to custom events
        def subscribe(event_pattern, &block)
          ActiveSupport::Notifications.subscribe(event_pattern, &block)
        end

        # Instrument a one-off event
        def instrument(event_name, payload = {}, &block)
          full_event_name = "#{event_name}.flow_chat"

          enriched_payload = {
            timestamp: Time.current
          }.merge(payload).compact

          ActiveSupport::Notifications.instrument(full_event_name, enriched_payload, &block)
        end

        # Access the metrics collector instance
        def metrics_collector
          @metrics_collector ||= FlowChat::Instrumentation::MetricsCollector.new
        end

        # Reset instrumentation (useful for testing)
        def reset!
          @log_subscriber_setup = false
          @metrics_collector_setup = false
          @log_subscriber = nil
          @metrics_collector = nil
        end

        private

        def setup_log_subscriber(options = {})
          # Check if Rails is available and use its initialization callback
          if defined?(Rails) && Rails.respond_to?(:application) && Rails.application
            Rails.application.config.after_initialize do
              initialize_log_subscriber
            end
          else
            # Initialize immediately for non-Rails environments
            initialize_log_subscriber
          end
        end

        def initialize_log_subscriber
          return if @log_subscriber

          @log_subscriber = FlowChat::Instrumentation::LogSubscriber.new

          # Manually subscribe to all FlowChat events
          subscribe_to_events
        end

        def subscribe_to_events
          # Core framework events
          subscribe_event("flow.execution.start.flow_chat", :flow_execution_start)
          subscribe_event("flow.execution.end.flow_chat", :flow_execution_end)
          subscribe_event("flow.execution.error.flow_chat", :flow_execution_error)

          # Session events
          subscribe_event("session.created.flow_chat", :session_created)
          subscribe_event("session.destroyed.flow_chat", :session_destroyed)
          subscribe_event("session.data.get.flow_chat", :session_data_get)
          subscribe_event("session.data.set.flow_chat", :session_data_set)
          subscribe_event("session.cache.hit.flow_chat", :session_cache_hit)
          subscribe_event("session.cache.miss.flow_chat", :session_cache_miss)

          # Platform-agnostic events (new scalable approach)
          subscribe_event("message.received.flow_chat", :message_received)
          subscribe_event("message.sent.flow_chat", :message_sent)
          subscribe_event("webhook.verified.flow_chat", :webhook_verified)
          subscribe_event("webhook.failed.flow_chat", :webhook_failed)
          subscribe_event("api.request.flow_chat", :api_request)
          subscribe_event("media.upload.flow_chat", :media_upload)
          subscribe_event("pagination.triggered.flow_chat", :pagination_triggered)

          # Middleware events
          subscribe_event("middleware.before.flow_chat", :middleware_before)
          subscribe_event("middleware.after.flow_chat", :middleware_after)

          # Context events
          subscribe_event("context.created.flow_chat", :context_created)
        end

        def subscribe_event(event_name, method_name)
          ActiveSupport::Notifications.subscribe(event_name) do |*args|
            event = ActiveSupport::Notifications::Event.new(*args)
            @log_subscriber.send(method_name, event) if @log_subscriber.respond_to?(method_name)
          end
        end

        def setup_metrics_collector(options = {})
          @metrics_collector = FlowChat::Instrumentation::MetricsCollector.new
        end
      end
    end
  end
end

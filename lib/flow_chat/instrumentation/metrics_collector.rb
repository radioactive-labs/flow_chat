module FlowChat
  module Instrumentation
    class MetricsCollector
      attr_reader :metrics

      def initialize
        @metrics = {}
        @mutex = Mutex.new
        subscribe_to_events
      end

      # Get current metrics snapshot
      def snapshot
        @mutex.synchronize { @metrics.dup }
      end

      # Reset all metrics
      def reset!
        @mutex.synchronize { @metrics.clear }
      end

      # Get metrics for a specific category
      def get_category(category)
        @mutex.synchronize do
          @metrics.select { |key, _| key.to_s.start_with?("#{category}.") }
        end
      end

      private

      def subscribe_to_events
        # Flow execution metrics
        ActiveSupport::Notifications.subscribe("flow.execution.end.flow_chat") do |event|
          increment_counter("flows.executed")
          track_timing("flows.execution_time", event.duration)
          increment_counter("flows.by_name.#{event.payload[:flow_name]}")
        end

        ActiveSupport::Notifications.subscribe("flow.execution.error.flow_chat") do |event|
          increment_counter("flows.errors")
          increment_counter("flows.errors.by_class.#{event.payload[:error_class]}")
          increment_counter("flows.errors.by_flow.#{event.payload[:flow_name]}")
        end

        # Session metrics
        ActiveSupport::Notifications.subscribe("session.created.flow_chat") do |event|
          increment_counter("sessions.created")
          increment_counter("sessions.created.by_gateway.#{event.payload[:gateway]}")
        end

        ActiveSupport::Notifications.subscribe("session.destroyed.flow_chat") do |event|
          increment_counter("sessions.destroyed")
        end

        ActiveSupport::Notifications.subscribe("session.cache.hit.flow_chat") do |event|
          increment_counter("sessions.cache.hits")
        end

        ActiveSupport::Notifications.subscribe("session.cache.miss.flow_chat") do |event|
          increment_counter("sessions.cache.misses")
        end

        ActiveSupport::Notifications.subscribe("session.data.get.flow_chat") do |event|
          increment_counter("sessions.data.get")
        end

        ActiveSupport::Notifications.subscribe("session.data.set.flow_chat") do |event|
          increment_counter("sessions.data.set")
        end

        ActiveSupport::Notifications.subscribe("message.received.flow_chat") do |event|
          platform = event.payload[:platform] || "unknown"
          increment_counter("#{platform}.messages.received")
          if event.payload[:message_type]
            increment_counter("#{platform}.messages.received.by_type.#{event.payload[:message_type]}")
          end
        end

        ActiveSupport::Notifications.subscribe("message.sent.flow_chat") do |event|
          platform = event.payload[:platform] || "unknown"
          increment_counter("#{platform}.messages.sent")
          if event.payload[:message_type]
            increment_counter("#{platform}.messages.sent.by_type.#{event.payload[:message_type]}")
          end
          track_timing("#{platform}.api.response_time", event.duration)
        end

        ActiveSupport::Notifications.subscribe("webhook.verified.flow_chat") do |event|
          platform = event.payload[:platform] || "unknown"
          increment_counter("#{platform}.webhook.verified")
        end

        ActiveSupport::Notifications.subscribe("webhook.failed.flow_chat") do |event|
          platform = event.payload[:platform] || "unknown"
          increment_counter("#{platform}.webhook.failures")
          if event.payload[:reason]
            increment_counter("#{platform}.webhook.failures.by_reason.#{event.payload[:reason]}")
          end
        end

        ActiveSupport::Notifications.subscribe("media.upload.flow_chat") do |event|
          platform = event.payload[:platform] || "unknown"
          if event.payload[:success] != false
            increment_counter("#{platform}.media.uploads.success")
            if event.payload[:size]
              track_histogram("#{platform}.media.upload_size", event.payload[:size])
            end
          else
            increment_counter("#{platform}.media.uploads.failure")
          end
          track_timing("#{platform}.media.upload_time", event.duration)
        end

        ActiveSupport::Notifications.subscribe("pagination.triggered.flow_chat") do |event|
          platform = event.payload[:platform] || "unknown"
          increment_counter("#{platform}.pagination.triggered")
          if event.payload[:content_length]
            track_histogram("#{platform}.pagination.content_length", event.payload[:content_length])
          end
        end

        ActiveSupport::Notifications.subscribe("api.request.flow_chat") do |event|
          platform = event.payload[:platform] || "unknown"
          if event.payload[:success]
            increment_counter("#{platform}.api.requests.success")
          else
            increment_counter("#{platform}.api.requests.failure")
            if event.payload[:status]
              increment_counter("#{platform}.api.requests.failure.by_status.#{event.payload[:status]}")
            end
          end
          track_timing("#{platform}.api.request_time", event.duration)
        end
      end

      def increment_counter(key, value = 1)
        @mutex.synchronize do
          @metrics[key] ||= 0
          @metrics[key] += value
        end
      end

      def track_timing(key, duration_ms)
        timing_key = "#{key}.timings"
        @mutex.synchronize do
          @metrics[timing_key] ||= []
          @metrics[timing_key] << duration_ms

          # Keep only last 1000 measurements for memory efficiency
          @metrics[timing_key] = @metrics[timing_key].last(1000) if @metrics[timing_key].size > 1000

          # Calculate and store aggregates
          timings = @metrics[timing_key]
          @metrics["#{key}.avg"] = timings.sum / timings.size
          @metrics["#{key}.min"] = timings.min
          @metrics["#{key}.max"] = timings.max
          @metrics["#{key}.p50"] = percentile(timings, 50)
          @metrics["#{key}.p95"] = percentile(timings, 95)
          @metrics["#{key}.p99"] = percentile(timings, 99)
        end
      end

      def track_histogram(key, value)
        histogram_key = "#{key}.histogram"
        @mutex.synchronize do
          @metrics[histogram_key] ||= []
          @metrics[histogram_key] << value

          # Keep only last 1000 measurements
          @metrics[histogram_key] = @metrics[histogram_key].last(1000) if @metrics[histogram_key].size > 1000

          # Calculate aggregates
          values = @metrics[histogram_key]
          @metrics["#{key}.total"] = values.sum
          @metrics["#{key}.avg"] = values.sum / values.size
          @metrics["#{key}.min"] = values.min
          @metrics["#{key}.max"] = values.max
        end
      end

      def percentile(array, percentile)
        return nil if array.empty?

        sorted = array.sort
        k = (percentile / 100.0) * (sorted.length - 1)
        f = k.floor
        c = k.ceil

        return sorted[k] if f == c

        d0 = sorted[f] * (c - k)
        d1 = sorted[c] * (k - f)
        d0 + d1
      end
    end
  end
end

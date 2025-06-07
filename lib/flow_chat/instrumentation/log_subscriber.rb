module FlowChat
  module Instrumentation
    class LogSubscriber
      # Flow execution events
      def flow_execution_start(event)
        payload = event.payload
        FlowChat.logger.info { "Flow Execution Started: #{payload[:flow_name]}##{payload[:action]} [Session: #{payload[:session_id]}]" }
      end

      def flow_execution_end(event)
        payload = event.payload
        duration = event.duration.round(2)
        FlowChat.logger.info { "Flow Execution Completed: #{payload[:flow_name]}##{payload[:action]} (#{duration}ms) [Session: #{payload[:session_id]}]" }
      end

      def flow_execution_error(event)
        payload = event.payload
        duration = event.duration.round(2)
        FlowChat.logger.error { "Flow Execution Failed: #{payload[:flow_name]}##{payload[:action]} (#{duration}ms) - #{payload[:error_class]}: #{payload[:error_message]} [Session: #{payload[:session_id]}]" }
      end

      # Session events
      def session_created(event)
        payload = event.payload
        FlowChat.logger.info { "Session Created: #{payload[:session_id]} [Store: #{payload[:store_type]}, Gateway: #{payload[:gateway]}]" }
      end

      def session_destroyed(event)
        payload = event.payload
        FlowChat.logger.info { "Session Destroyed: #{payload[:session_id]} [Gateway: #{payload[:gateway]}]" }
      end

      def session_cache_hit(event)
        payload = event.payload
        FlowChat.logger.debug { "Session Cache Hit: #{payload[:session_id]} - Key: #{payload[:key]}" }
      end

      def session_cache_miss(event)
        payload = event.payload
        FlowChat.logger.debug { "Session Cache Miss: #{payload[:session_id]} - Key: #{payload[:key]}" }
      end

      def session_data_set(event)
        payload = event.payload
        FlowChat.logger.debug { "Session Data Set: #{payload[:session_id]} - Key: #{payload[:key]}" }
      end

      def session_data_get(event)
        payload = event.payload
        FlowChat.logger.debug { "Session Data Get: #{payload[:session_id]} - Key: #{payload[:key]} = #{payload[:value].inspect}" }
      end

      # Middleware events
      def middleware_before(event)
        payload = event.payload
        FlowChat.logger.debug { "Middleware Before: #{payload[:middleware_name]} [Session: #{payload[:session_id]}]" }
      end

      def middleware_after(event)
        payload = event.payload
        duration = event.duration.round(2)
        FlowChat.logger.debug { "Middleware After: #{payload[:middleware_name]} (#{duration}ms) [Session: #{payload[:session_id]}]" }
      end

      # Platform-agnostic events (new scalable approach)
      def message_received(event)
        payload = event.payload
        platform = payload[:platform] || "unknown"
        platform_name = format_platform_name(platform)

        case platform.to_sym
        when :whatsapp
          contact_info = payload[:contact_name] ? " (#{payload[:contact_name]})" : ""
          FlowChat.logger.info { "#{platform_name} Message Received: #{payload[:from]}#{contact_info} - Type: #{payload[:message_type]} [ID: #{payload[:message_id]}]" }
        when :ussd
          FlowChat.logger.info { "#{platform_name} Message Received: #{payload[:from]} - Input: '#{payload[:message]}' [Session: #{payload[:session_id]}]" }
        else
          FlowChat.logger.info { "#{platform_name} Message Received: #{payload[:from]} - Message: '#{payload[:message]}' [Session: #{payload[:session_id]}]" }
        end
      end

      def message_sent(event)
        payload = event.payload
        platform = payload[:platform] || "unknown"
        platform_name = format_platform_name(platform)
        duration = event.duration.round(2)

        case platform.to_sym
        when :whatsapp
          FlowChat.logger.info { "#{platform_name} Message Sent: #{payload[:to]} - Type: #{payload[:message_type]} (#{duration}ms) [Length: #{payload[:content_length]} chars]" }
        when :ussd
          FlowChat.logger.info { "#{platform_name} Message Sent: #{payload[:to]} - Type: #{payload[:message_type]} (#{duration}ms) [Session: #{payload[:session_id]}]" }
        else
          FlowChat.logger.info { "#{platform_name} Message Sent: #{payload[:to]} - Type: #{payload[:message_type]} (#{duration}ms)" }
        end
      end

      def webhook_verified(event)
        payload = event.payload
        platform = payload[:platform] || "unknown"
        platform_name = format_platform_name(platform)
        FlowChat.logger.info { "#{platform_name} Webhook Verified Successfully [Challenge: #{payload[:challenge]}]" }
      end

      def webhook_failed(event)
        payload = event.payload
        platform = payload[:platform] || "unknown"
        platform_name = format_platform_name(platform)
        FlowChat.logger.warn { "#{platform_name} Webhook Verification Failed: #{payload[:reason]}" }
      end

      def media_upload(event)
        payload = event.payload
        platform = payload[:platform] || "unknown"
        platform_name = format_platform_name(platform)
        duration = event.duration.round(2)

        if payload[:success] != false  # Check for explicit false, not just falsy
          FlowChat.logger.info { "#{platform_name} Media Upload: #{payload[:filename]} (#{format_bytes(payload[:size])}, #{duration}ms) - Success" }
        else
          FlowChat.logger.error { "#{platform_name} Media Upload Failed: #{payload[:filename]} (#{duration}ms) - #{payload[:error]}" }
        end
      end

      def pagination_triggered(event)
        payload = event.payload
        platform = payload[:platform] || "unknown"
        platform_name = format_platform_name(platform)
        FlowChat.logger.info { "#{platform_name} Pagination Triggered: Page #{payload[:current_page]}/#{payload[:total_pages]} (#{payload[:content_length]} chars) [Session: #{payload[:session_id]}]" }
      end

      def api_request(event)
        payload = event.payload
        platform = payload[:platform] || "unknown"
        platform_name = format_platform_name(platform)
        duration = event.duration.round(2)

        if payload[:success]
          FlowChat.logger.debug { "#{platform_name} API Request: #{payload[:method]} #{payload[:endpoint]} (#{duration}ms) - Success" }
        else
          FlowChat.logger.error { "#{platform_name} API Request: #{payload[:method]} #{payload[:endpoint]} (#{duration}ms) - Failed: #{payload[:status]} #{payload[:error]}" }
        end
      end

      # Context events
      def context_created(event)
        payload = event.payload
        FlowChat.logger.debug { "Context Created [Gateway: #{payload[:gateway] || "unknown"}]" }
      end

      private

      # Format platform name for display
      def format_platform_name(platform)
        case platform.to_sym
        when :whatsapp then "WhatsApp"
        when :ussd then "USSD"
        else platform.to_s.capitalize
        end
      end

      # Format bytes in a human-readable way
      def format_bytes(bytes)
        return "unknown size" unless bytes

        if bytes < 1024
          "#{bytes} bytes"
        elsif bytes < 1024 * 1024
          "#{(bytes / 1024.0).round(1)} KB"
        else
          "#{(bytes / (1024.0 * 1024.0)).round(1)} MB"
        end
      end
    end
  end
end

module FlowChat
  module Whatsapp
    # Module to be included in background jobs for WhatsApp response delivery
    # Only handles sending responses, not processing flows
    module SendJobSupport
      extend ActiveSupport::Concern

      included do
        # Set up job configuration
        queue_as :default
        retry_on StandardError, wait: :exponentially_longer, attempts: 3
      end

      # Main job execution method for sending responses
      def perform_whatsapp_send(send_data)
        config = resolve_whatsapp_config(send_data)
        client = FlowChat::Whatsapp::Client.new(config)
        
        result = client.send_message(send_data[:msisdn], send_data[:response])
        
        if result
          Rails.logger.info "WhatsApp message sent successfully: #{result['messages']&.first&.dig('id')}"
          on_whatsapp_send_success(send_data, result)
        else
          Rails.logger.error "Failed to send WhatsApp message to #{send_data[:msisdn]}"
          raise "WhatsApp API call failed"
        end
      rescue => e
        on_whatsapp_send_error(e, send_data)
        handle_whatsapp_send_error(e, send_data, config)
      end

      private

      # Resolve WhatsApp configuration by name or fallback
      def resolve_whatsapp_config(send_data)
        # Try to resolve by name first (preferred method)
        if send_data[:config_name] && FlowChat::Whatsapp::Configuration.exists?(send_data[:config_name])
          return FlowChat::Whatsapp::Configuration.get(send_data[:config_name])
        end

        # Final fallback to default configuration
        FlowChat::Whatsapp::Configuration.from_credentials
      end

      # Handle errors with user notification
      def handle_whatsapp_send_error(error, send_data, config = nil)
        Rails.logger.error "WhatsApp send job error: #{error.message}"
        Rails.logger.error error.backtrace&.join("\n") if error.backtrace
        
        # Try to send error message to user if we have config
        if config
          begin
            client = FlowChat::Whatsapp::Client.new(config)
            client.send_text(
              send_data[:msisdn], 
              "⚠️ We're experiencing technical difficulties. Please try again in a few minutes."
            )
          rescue => send_error
            Rails.logger.error "Failed to send error message: #{send_error.message}"
          end
        end
        
        # Re-raise for job retry logic
        raise error
      end

      # Override this method in your job for custom behavior
      def on_whatsapp_send_success(send_data, result)
        # Optional callback for successful message sending
      end

      # Override this method in your job for custom error handling
      def on_whatsapp_send_error(error, send_data)
        # Optional callback for error handling
      end
    end
  end
end 
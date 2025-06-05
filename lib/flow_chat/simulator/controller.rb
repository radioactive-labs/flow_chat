module FlowChat
  module Simulator
    module Controller
      def flowchat_simulator
        # Set simulator cookie for authentication
        set_simulator_cookie
        
        respond_to do |format|
          format.html do
            render inline: simulator_view_template, layout: false, locals: simulator_locals
          end
        end
      end

      protected

      def default_phone_number
        "+233244123456"
      end

      def default_contact_name
        "John Doe"
      end

      def default_config_key
        "ussd"
      end

      def simulator_configurations
        {
          "ussd" => {
            name: "USSD (Nalo)",
            description: "USSD integration using Nalo",
            processor_type: "ussd",
            provider: "nalo",
            endpoint: "/ussd",
            icon: "📱",
            color: "#28a745",
            settings: {
              phone_number: default_phone_number,
              session_timeout: 300
            }
          },
          "whatsapp" => {
            name: "WhatsApp (Cloud API)",
            description: "WhatsApp integration using Cloud API",
            processor_type: "whatsapp",
            provider: "cloud_api",
            endpoint: "/whatsapp/webhook",
            icon: "💬",
            color: "#25D366",
            settings: {
              phone_number: default_phone_number,
              contact_name: default_contact_name,
            }
          }
        }
      end

      def simulator_view_template
        File.read simulator_view_path
      end

      def simulator_view_path
        File.join FlowChat.root.join("flow_chat", "simulator", "views", "simulator.html.erb")
      end

      def simulator_locals
        {
          pagesize: FlowChat::Config.ussd.pagination_page_size,
          default_phone_number: default_phone_number,
          default_contact_name: default_contact_name,
          default_config_key: default_config_key,
          configurations: simulator_configurations
        }
      end

      def set_simulator_cookie
        # Get global simulator secret
        simulator_secret = FlowChat::Config.simulator_secret
        
        unless simulator_secret && !simulator_secret.empty?
          raise StandardError, "Simulator secret not configured. Please set FlowChat::Config.simulator_secret to enable simulator mode."
        end
        
        # Generate timestamp-based signed cookie
        timestamp = Time.now.to_i
        message = "simulator:#{timestamp}"
        signature = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), simulator_secret, message)
        
        cookie_value = "#{timestamp}:#{signature}"
        
        # Set secure cookie (valid for 24 hours)
        cookies[:flowchat_simulator] = {
          value: cookie_value,
          expires: 24.hours.from_now,
          secure: request.ssl?, # Only send over HTTPS in production
          httponly: true,       # Prevent XSS access
          same_site: :lax      # CSRF protection while allowing normal navigation
        }
      rescue => e
        Rails.logger.warn "Failed to set simulator cookie: #{e.message}"
        raise e # Re-raise the exception so it's not silently ignored
      end
    end
  end
end

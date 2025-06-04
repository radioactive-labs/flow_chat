module FlowChat
  module Simulator
    module Controller
      def flowchat_simulator
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
            description: "Local development USSD testing",
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
            name: "WhatsApp",
            description: "Local development WhatsApp testing",
            processor_type: "whatsapp",
            provider: "cloud_api",
            endpoint: "/whatsapp/webhook",
            icon: "💬",
            color: "#25D366",
            settings: {
              phone_number: default_phone_number,
              contact_name: default_contact_name,
              verify_token: "local_verify_token",
              webhook_url: "http://localhost:3000/whatsapp/webhook"
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
    end
  end
end

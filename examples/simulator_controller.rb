# Example Simulator Controller
# Add this to your Rails application as app/controllers/simulator_controller.rb

class SimulatorController < ApplicationController
  include FlowChat::Simulator::Controller

  def index
    flowchat_simulator
  end

  protected

  # Define different endpoints to test
  def configurations
    {
      ussd_main: {
        name: "Main USSD Endpoint",
        description: "Primary USSD integration",
        processor_type: "ussd",
        gateway: "nalo",
        endpoint: "/ussd",
        icon: "📱",
        color: "#28a745"
      },
      whatsapp_main: {
        name: "Main WhatsApp Endpoint",
        description: "Primary WhatsApp webhook",
        processor_type: "whatsapp",
        gateway: "cloud_api",
        endpoint: "/whatsapp/webhook",
        icon: "💬",
        color: "#25D366"
      },
      whatsapp_tenant_a: {
        name: "Tenant A WhatsApp",
        description: "Multi-tenant endpoint for Tenant A",
        processor_type: "whatsapp",
        gateway: "cloud_api",
        endpoint: "/tenants/a/whatsapp/webhook",
        icon: "🏢",
        color: "#fd7e14"
      },
      whatsapp_legacy: {
        name: "Legacy WhatsApp",
        description: "Legacy endpoint for compatibility",
        processor_type: "whatsapp",
        gateway: "cloud_api",
        endpoint: "/legacy/whatsapp",
        icon: "📦",
        color: "#6c757d"
      }
    }
  end

  # Default configuration to start with
  def default_config_key
    :whatsapp_main
  end

  # Default test phone number
  def default_phone_number
    "+1234567890"
  end

  # Default test contact name
  def default_contact_name
    "Test User"
  end
end

# Add this route to your config/routes.rb:
# get '/simulator' => 'simulator#index'

# Usage:
# 1. Start your Rails server: rails server
# 2. Visit http://localhost:3000/simulator
# 3. Select different endpoints from the dropdown to test
# 4. Send test messages to see how each endpoint responds
# 5. View request/response logs in real-time

# This allows you to test:
# - Different controller implementations on the same server
# - Different API versions (v1, v2, etc.)
# - Multi-tenant endpoints with different configurations
# - Legacy endpoints alongside new ones
# - Different flow implementations for different endpoints

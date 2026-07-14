# Example configuration for using FlowChat with Intercom

# 1. Rails Credentials Configuration (recommended)
# Run: rails credentials:edit
# Add to config/credentials.yml.enc:

# intercom:
#   access_token: "your_intercom_access_token_here"
#   client_secret: "your_intercom_client_secret_here"  # For webhook signature validation
#   admin_id: "your_admin_id_here"  # Required - admin ID for sending messages
#   skip_signature_validation: false  # Set to true for development/testing

# 2. Environment Variables Configuration (alternative)
# Set these environment variables:

# INTERCOM_ACCESS_TOKEN=your_intercom_access_token_here
# INTERCOM_CLIENT_SECRET=your_intercom_client_secret_here
# INTERCOM_ADMIN_ID=your_admin_id_here
# INTERCOM_SKIP_SIGNATURE_VALIDATION=false

# 3. Named Configuration Example (for multi-tenant apps)
class MultiTenantIntercomSetup
  def self.setup_configurations
    # Passing a name registers the configuration under that name, so you can
    # fetch it later with Configuration.get(:main). Set attributes with tap;
    # Configuration.new does not yield a block.
    FlowChat::Intercom::Configuration.new("main").tap do |config|
      config.access_token = Rails.application.credentials.dig(:intercom, :main, :access_token)
      config.client_secret = Rails.application.credentials.dig(:intercom, :main, :client_secret)
      config.admin_id = Rails.application.credentials.dig(:intercom, :main, :admin_id)
    end

    # Enterprise customer configuration
    FlowChat::Intercom::Configuration.new("enterprise").tap do |config|
      config.access_token = Rails.application.credentials.dig(:intercom, :enterprise, :access_token)
      config.client_secret = Rails.application.credentials.dig(:intercom, :enterprise, :client_secret)
      config.admin_id = Rails.application.credentials.dig(:intercom, :enterprise, :admin_id)
    end
  end
end

# 4. Routes Configuration
# Add to config/routes.rb:

# Rails.application.routes.draw do
#   # Intercom webhook endpoint - supports both HEAD (for URL validation) and POST (for events)
#   match '/intercom/webhook', to: 'intercom#webhook', via: [:head, :post]
#
#   # Multiple tenant support (if needed)
#   match '/intercom/:tenant/webhook', to: 'intercom#webhook', via: [:head, :post]
# end

# 5. Controller with Named Configuration
class TenantAwareIntercomController < ApplicationController
  skip_forgery_protection

  def webhook
    # Fetch the named configuration registered in setup_configurations above.
    tenant = params[:tenant] || "main"
    tenant_config = FlowChat::Intercom::Configuration.get(tenant)

    processor = FlowChat::Processor.new(self) do |config|
      config.use_gateway FlowChat::Intercom::Gateway::IntercomApi, tenant_config
      config.use_session_store FlowChat::Session::CacheSessionStore
      config.use_session_config(
        boundaries: [:flow, :url],  # Separate sessions per tenant
        identifier: :conversation_id
      )
    end

    processor.run CustomerSupportFlow, :handle_conversation
  end
end

# 6. Intercom Webhook Setup Instructions
# To set up webhooks in Intercom:
#
# 1. Go to your Intercom Developer Hub
# 2. Navigate to Configure → Webhooks
# 3. Add your webhook endpoint:
#    - Endpoint URL: https://yourdomain.com/intercom/webhook (must use HTTPS)
#    - Intercom will send a HEAD request to validate your URL
#    - Your app automatically responds with 200 OK
#
# 4. Subscribe to webhook topics:
#    - conversation.user.created (new conversations)
#    - conversation.user.replied (user replies)
#
# 5. Configure signature validation:
#    - Find your app's Client Secret in Basic Information
#    - Add this as client_secret in your Rails credentials
#    - Webhooks are validated using X-Hub-Signature header with SHA1 HMAC
#
# 6. Test the webhook:
#    - Send a test message in Intercom
#    - Verify your endpoint receives the webhook notification
#    - Check logs for any signature validation issues

# 7. Finding Your Admin ID (Required)
# To find your admin ID for message sending, use this Rails console command:
#
#   rails console
#   ```
#     config = FlowChat::Intercom::Configuration.from_credentials
#     client = FlowChat::Intercom::Client.new(config)
#     result = client.list_admins
#     result["admins"].each { |admin| puts "#{admin["name"]} (#{admin["email"]}) - ID: #{admin["id"]}" }
#   ```
#
# This will display all admins with their IDs. Copy the ID of the admin you want to use for sending messages.
#
# Alternative methods:
# 1. Go to your Intercom Developer Hub (https://developers.intercom.com/)
# 2. Navigate to your app → Configure → Basic Information
# 3. Find the Admin ID in the app details
#
# The admin_id is required for sending messages from FlowChat to Intercom conversations.
# The API uses this to identify which admin is sending the message.
#
# Note: The old bot_user_id configuration is no longer needed.

# Example Multi-Tenant WhatsApp Controller
# This shows how to configure different WhatsApp accounts per tenant/client

# Controller supporting multiple WhatsApp accounts per tenant
class MultiTenantWhatsappController < ApplicationController
  skip_forgery_protection

  def webhook
    tenant = determine_tenant(request)
    whatsapp_config = get_whatsapp_config_for_tenant(tenant)

    processor = FlowChat::Whatsapp::Processor.new(self, enable_simulator: !Rails.env.production?) do |config|
      config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi, whatsapp_config
      config.use_session_store FlowChat::Session::CacheSessionStore
    end

    flow_class = get_flow_for_tenant(tenant)
    processor.run flow_class, :main_page
  end

  private

  def determine_tenant(request)
    # Option 1: From subdomain
    return request.subdomain if request.subdomain.present?

    # Option 2: From path (e.g., /whatsapp/acme/webhook)
    tenant_from_path = request.path.match(%r{^/whatsapp/(\w+)/})&.captures&.first
    return tenant_from_path if tenant_from_path

    # Option 3: From header
    return request.headers["X-Tenant-ID"] if request.headers["X-Tenant-ID"]

    "default"
  end

  def get_whatsapp_config_for_tenant(tenant)
    case tenant
    when "acme_corp"
      FlowChat::Whatsapp::Configuration.new.tap do |config|
        config.access_token = ENV["ACME_WHATSAPP_ACCESS_TOKEN"]
        config.phone_number_id = ENV["ACME_WHATSAPP_PHONE_NUMBER_ID"]
        config.verify_token = ENV["ACME_WHATSAPP_VERIFY_TOKEN"]
        config.app_secret = ENV["ACME_WHATSAPP_APP_SECRET"]
      end

    when "tech_startup"
      FlowChat::Whatsapp::Configuration.new.tap do |config|
        config.access_token = ENV["TECHSTARTUP_WHATSAPP_ACCESS_TOKEN"]
        config.phone_number_id = ENV["TECHSTARTUP_WHATSAPP_PHONE_NUMBER_ID"]
        config.verify_token = ENV["TECHSTARTUP_WHATSAPP_VERIFY_TOKEN"]
        config.app_secret = ENV["TECHSTARTUP_WHATSAPP_APP_SECRET"]
      end

    when "retail_store"
      # Load from database
      tenant_config = WhatsappConfiguration.find_by(tenant: tenant)
      FlowChat::Whatsapp::Configuration.new.tap do |config|
        config.access_token = tenant_config.access_token
        config.phone_number_id = tenant_config.phone_number_id
        config.verify_token = tenant_config.verify_token
        config.app_secret = tenant_config.app_secret
      end

    else
      FlowChat::Whatsapp::Configuration.from_credentials
    end
  end

  def get_flow_for_tenant(tenant)
    case tenant
    when "acme_corp"
      AcmeCorpFlow
    when "tech_startup"
      TechStartupFlow
    when "retail_store"
      RetailStoreFlow
    else
      WelcomeFlow
    end
  end
end

# Example: Dynamic Configuration from Database
class DatabaseWhatsappController < ApplicationController
  skip_forgery_protection

  def webhook
    business_account = find_business_account(params)
    return head :not_found if business_account.nil?

    whatsapp_config = FlowChat::Whatsapp::Configuration.new.tap do |config|
      config.access_token = business_account.whatsapp_access_token
      config.phone_number_id = business_account.whatsapp_phone_number_id
      config.verify_token = business_account.whatsapp_verify_token
      config.app_secret = business_account.whatsapp_app_secret
    end

    processor = FlowChat::Whatsapp::Processor.new(self) do |config|
      config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi, whatsapp_config
      config.use_session_store FlowChat::Session::CacheSessionStore
    end

    processor.run business_account.flow_class.constantize, :main_page
  end

  private

  def find_business_account(params)
    # Find by phone number ID from webhook
    phone_number_id = extract_phone_number_id_from_webhook(params)
    BusinessAccount.find_by(whatsapp_phone_number_id: phone_number_id)
  end

  def extract_phone_number_id_from_webhook(params)
    # Extract from webhook payload - implement based on your structure
    params.dig(:entry, 0, :changes, 0, :value, :metadata, :phone_number_id)
  end
end

# Example: Environment-based Configuration
class EnvironmentWhatsappController < ApplicationController
  skip_forgery_protection

  def webhook
    # Different configurations for different environments
    whatsapp_config = case Rails.env
    when "production"
      production_whatsapp_config
    when "staging"
      staging_whatsapp_config
    when "development"
      development_whatsapp_config
    else
      FlowChat::Whatsapp::Configuration.from_credentials
    end

    processor = FlowChat::Whatsapp::Processor.new(self) do |config|
      config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi, whatsapp_config
      config.use_session_store FlowChat::Session::CacheSessionStore
    end

    processor.run WelcomeFlow, :main_page
  end

  private

  def production_whatsapp_config
    FlowChat::Whatsapp::Configuration.new.tap do |config|
      config.access_token = ENV["PROD_WHATSAPP_ACCESS_TOKEN"]
      config.phone_number_id = ENV["PROD_WHATSAPP_PHONE_NUMBER_ID"]
      config.verify_token = ENV["PROD_WHATSAPP_VERIFY_TOKEN"]
      config.app_id = ENV["PROD_WHATSAPP_APP_ID"]
      config.app_secret = ENV["PROD_WHATSAPP_APP_SECRET"]
      config.business_account_id = ENV["PROD_WHATSAPP_BUSINESS_ACCOUNT_ID"]
    end
  end

  def staging_whatsapp_config
    FlowChat::Whatsapp::Configuration.new.tap do |config|
      config.access_token = ENV["STAGING_WHATSAPP_ACCESS_TOKEN"]
      config.phone_number_id = ENV["STAGING_WHATSAPP_PHONE_NUMBER_ID"]
      config.verify_token = ENV["STAGING_WHATSAPP_VERIFY_TOKEN"]
      config.app_id = ENV["STAGING_WHATSAPP_APP_ID"]
      config.app_secret = ENV["STAGING_WHATSAPP_APP_SECRET"]
      config.business_account_id = ENV["STAGING_WHATSAPP_BUSINESS_ACCOUNT_ID"]
    end
  end

  def development_whatsapp_config
    FlowChat::Whatsapp::Configuration.new.tap do |config|
      config.access_token = ENV["DEV_WHATSAPP_ACCESS_TOKEN"]
      config.phone_number_id = ENV["DEV_WHATSAPP_PHONE_NUMBER_ID"]
      config.verify_token = ENV["DEV_WHATSAPP_VERIFY_TOKEN"]
      config.app_id = ENV["DEV_WHATSAPP_APP_ID"]
      config.app_secret = ENV["DEV_WHATSAPP_APP_SECRET"]
      config.business_account_id = ENV["DEV_WHATSAPP_BUSINESS_ACCOUNT_ID"]
    end
  end
end

# Example: Simple Custom Configuration
class CustomWhatsappController < ApplicationController
  skip_forgery_protection

  def webhook
    # Create custom configuration for this specific endpoint
    my_config = FlowChat::Whatsapp::Configuration.new
    my_config.access_token = "EAABs..." # Your specific access token
    my_config.phone_number_id = "123456789"
    my_config.verify_token = "my_verify_token"
    my_config.app_id = "your_app_id"
    my_config.app_secret = "your_app_secret"
    my_config.business_account_id = "your_business_account_id"

    processor = FlowChat::Whatsapp::Processor.new(self) do |config|
      config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi, my_config
      config.use_session_store FlowChat::Session::CacheSessionStore
    end

    processor.run CustomFlow, :main_page
  end
end

# Add routes for different tenants:
# Rails.application.routes.draw do
#   # Subdomain-based routing
#   constraints subdomain: /\w+/ do
#     post '/whatsapp/webhook', to: 'multi_tenant_whatsapp#webhook'
#   end
#
#   # Path-based routing
#   post '/whatsapp/:tenant/webhook', to: 'multi_tenant_whatsapp#webhook'
#
#   # Environment-specific
#   post '/whatsapp/env/webhook', to: 'environment_whatsapp#webhook'
#
#   # Custom endpoint
#   post '/whatsapp/custom/webhook', to: 'custom_whatsapp#webhook'
# end

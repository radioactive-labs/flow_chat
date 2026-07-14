# Example Multi-Tenant WhatsApp Controller
# Shows how to run different WhatsApp accounts per tenant on one endpoint.

# A single helper builds a Configuration from a set of environment variables,
# so each tenant is one line instead of a repeated block. Pass an anonymous
# configuration name (nil); Configuration#initialize requires a name argument.
module WhatsappConfigBuilder
  def whatsapp_config_from_env(prefix)
    FlowChat::Whatsapp::Configuration.new(nil).tap do |config|
      config.access_token = ENV["#{prefix}_WHATSAPP_ACCESS_TOKEN"]
      config.phone_number_id = ENV["#{prefix}_WHATSAPP_PHONE_NUMBER_ID"]
      config.verify_token = ENV["#{prefix}_WHATSAPP_VERIFY_TOKEN"]
      config.app_secret = ENV["#{prefix}_WHATSAPP_APP_SECRET"]
    end
  end
end

# Controller supporting multiple WhatsApp accounts per tenant.
class MultiTenantWhatsappController < ApplicationController
  include WhatsappConfigBuilder

  skip_forgery_protection

  def webhook
    tenant = determine_tenant(request)
    whatsapp_config = config_for_tenant(tenant)

    processor = FlowChat::Processor.new(self, enable_simulator: !Rails.env.production?) do |config|
      config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi, whatsapp_config
      config.use_session_store FlowChat::Session::CacheSessionStore
    end

    processor.run flow_for_tenant(tenant), :main_page
  end

  private

  def determine_tenant(request)
    return request.subdomain if request.subdomain.present?

    tenant_from_path = request.path.match(%r{^/whatsapp/(\w+)/})&.captures&.first
    return tenant_from_path if tenant_from_path

    request.headers["X-Tenant-ID"].presence || "default"
  end

  def config_for_tenant(tenant)
    case tenant
    when "acme_corp" then whatsapp_config_from_env("ACME")
    when "tech_startup" then whatsapp_config_from_env("TECHSTARTUP")
    when "retail_store" then config_from_database(tenant)
    else FlowChat::Whatsapp::Configuration.from_credentials
    end
  end

  # Load a tenant's credentials from your own model.
  def config_from_database(tenant)
    record = WhatsappConfiguration.find_by!(tenant: tenant)
    FlowChat::Whatsapp::Configuration.new(nil).tap do |config|
      config.access_token = record.access_token
      config.phone_number_id = record.phone_number_id
      config.verify_token = record.verify_token
      config.app_secret = record.app_secret
    end
  end

  def flow_for_tenant(tenant)
    {
      "acme_corp" => AcmeCorpFlow,
      "tech_startup" => TechStartupFlow,
      "retail_store" => RetailStoreFlow
    }.fetch(tenant, WhatsappWelcomeFlow)
  end
end

# Resolve the account from the webhook's own phone_number_id, rather than the URL.
class DatabaseWhatsappController < ApplicationController
  include WhatsappConfigBuilder

  skip_forgery_protection

  def webhook
    account = find_business_account(params)
    return head :not_found if account.nil?

    whatsapp_config = FlowChat::Whatsapp::Configuration.new(nil).tap do |config|
      config.access_token = account.whatsapp_access_token
      config.phone_number_id = account.whatsapp_phone_number_id
      config.verify_token = account.whatsapp_verify_token
      config.app_secret = account.whatsapp_app_secret
    end

    processor = FlowChat::Processor.new(self) do |config|
      config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi, whatsapp_config
      config.use_session_store FlowChat::Session::CacheSessionStore
    end

    processor.run account.flow_class.constantize, :main_page
  end

  private

  def find_business_account(params)
    phone_number_id = params.dig(:entry, 0, :changes, 0, :value, :metadata, :phone_number_id)
    BusinessAccount.find_by(whatsapp_phone_number_id: phone_number_id)
  end
end

# Add routes for the tenant endpoints, for example:
#   Rails.application.routes.draw do
#     constraints subdomain: /\w+/ do
#       post "/whatsapp/webhook", to: "multi_tenant_whatsapp#webhook"
#     end
#     post "/whatsapp/:tenant/webhook", to: "multi_tenant_whatsapp#webhook"
#   end

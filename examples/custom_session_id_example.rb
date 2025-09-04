# frozen_string_literal: true

# Example: Custom Session ID Configuration with Proc
#
# This example demonstrates how to use a custom proc for session ID generation
# in FlowChat applications. The proc allows complete customization of how 
# session IDs are generated based on context data.

require "flow_chat"

class CustomSessionIdController < ApplicationController
  def ussd_endpoint
    processor = FlowChat::Processor.new(self) do |config|
      config.use_gateway FlowChat::Ussd::Gateway::Nalo
      config.use_session_store FlowChat::Session::RailsSessionStore
      
      # Example 1: Custom session ID using block/proc
      config.use_session_config do |context|
        # Create a custom session ID based on your business logic
        user_phone = context["request.msisdn"]
        flow_name = context["flow.name"]
        gateway = context["request.gateway"]
        timestamp = Time.current.strftime("%Y%m%d")
        
        # Custom format: flow_gateway_date_hashedphone
        "#{flow_name}_#{gateway}_#{timestamp}_#{hash_phone(user_phone)}"
      end
    end

    processor.run(SurveyFlow, :main_menu)
  end

  def whatsapp_endpoint
    processor = FlowChat::Processor.new(self) do |config|
      config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
      config.use_session_store FlowChat::Session::CacheSessionStore
      
      # Example 2: Multi-tenant session IDs
      config.use_session_config do |context|
        tenant_id = extract_tenant_from_request(context)
        user_id = context["request.user_id"] || context["request.msisdn"]
        flow_name = context["flow.name"]
        
        "tenant_#{tenant_id}_flow_#{flow_name}_user_#{hash_identifier(user_id)}"
      end
    end

    processor.run(CustomerSupportFlow, :handle_inquiry)
  end

  def http_endpoint
    processor = FlowChat::Processor.new(self) do |config|
      config.use_gateway FlowChat::Http::Gateway::Simple
      config.use_session_store FlowChat::Session::RailsSessionStore
      
      # Example 3: API session with custom expiration tracking
      config.use_session_config do |context|
        api_key = context.controller.request.headers["X-API-Key"]
        request_id = context["request.id"]
        
        # Include API key hash for session isolation per API client
        "api_#{hash_identifier(api_key)}_req_#{request_id}"
      end
    end

    processor.run(ApiFlow, :handle_request)
  end

  private

  def hash_phone(phone)
    require "digest"
    Digest::SHA256.hexdigest(phone)[0, 8]
  end

  def hash_identifier(identifier)
    require "digest"
    Digest::SHA256.hexdigest(identifier.to_s)[0, 8]
  end

  def extract_tenant_from_request(context)
    # Extract tenant from subdomain or header
    request = context.controller&.request
    return "default" unless request
    
    host = request.host
    subdomain = host.split(".").first
    subdomain if subdomain != "www"
  end
end

# Example flows for demonstration
class SurveyFlow < FlowChat::Flow
  def main_menu
    app.screen(:menu) { |p| p.ask "Welcome! Choose an option:", choices: ["Survey", "Exit"] }
  end
end

class CustomerSupportFlow < FlowChat::Flow
  def handle_inquiry
    app.screen(:inquiry) { |p| p.ask "How can we help you today?" }
  end
end

class ApiFlow < FlowChat::Flow
  def handle_request
    app.screen(:request) { |p| p.ask "API request received. Provide data:" }
  end
end

# Note: The custom session ID proc approach provides:
# - Complete control over session ID format
# - Access to full context (request data, flow info, etc.)
# - Ability to implement complex business logic
# - Support for multi-tenancy, API authentication, etc.
#
# The proc should return a string that will be used as the session ID.
# Make sure the returned ID is unique for your use case to avoid 
# session collisions.
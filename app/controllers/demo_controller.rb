# Demo Controller - Showcases FlowChat comprehensive features
# 
# This controller demonstrates how to use the DemoRestaurantFlow
# across both USSD and WhatsApp platforms, showing off all FlowChat features.
#
# Features demonstrated:
# - Cross-platform compatibility
# - Media support with graceful degradation  
# - Complex workflows with session management
# - Input validation and transformation
# - Rich interactive elements

class DemoController < ApplicationController
  skip_forgery_protection

  # USSD Demo Endpoint
  # Usage: POST /demo/ussd
  def ussd_demo
    processor = FlowChat::Ussd::Processor.new(self) do |config|
      config.use_gateway FlowChat::Ussd::Gateway::Nalo
      config.use_session_store FlowChat::Session::RailsSessionStore
      
      # Optional: Enable resumable sessions for better UX
      config.use_resumable_sessions
      
      # Optional: Custom pagination settings for large menus
      FlowChat::Config.ussd.pagination_page_size = 120  # Slightly larger for demo
    end

    processor.run DemoRestaurantFlow, :main_page
  end

  # WhatsApp Demo Endpoint  
  # Usage: GET/POST /demo/whatsapp
  def whatsapp_demo
    processor = FlowChat::Whatsapp::Processor.new(self, enable_simulator: Rails.env.development?) do |config|
      config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
      config.use_session_store FlowChat::Session::CacheSessionStore
    end

    processor.run DemoRestaurantFlow, :main_page
  end

  # Alternative WhatsApp Demo with Custom Configuration
  # Usage: GET/POST /demo/whatsapp_custom
  def whatsapp_custom_demo
    # Custom configuration for multi-tenant demo
    custom_config = FlowChat::Whatsapp::Configuration.new
    custom_config.access_token = ENV['DEMO_WHATSAPP_ACCESS_TOKEN']
    custom_config.phone_number_id = ENV['DEMO_WHATSAPP_PHONE_NUMBER_ID']
    custom_config.verify_token = ENV['DEMO_WHATSAPP_VERIFY_TOKEN']
    custom_config.app_secret = ENV['DEMO_WHATSAPP_APP_SECRET']
    custom_config.skip_signature_validation = Rails.env.development?

    processor = FlowChat::Whatsapp::Processor.new(self, enable_simulator: true) do |config|
      config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi, custom_config
      config.use_session_store FlowChat::Session::CacheSessionStore
    end

    processor.run DemoRestaurantFlow, :main_page
  end

  # Background Mode Demo
  # Usage: GET/POST /demo/whatsapp_background
  def whatsapp_background_demo
    # Configure for background processing
    original_mode = FlowChat::Config.whatsapp.message_handling_mode
    FlowChat::Config.whatsapp.message_handling_mode = :background
    FlowChat::Config.whatsapp.background_job_class = 'DemoWhatsappJob'

    processor = FlowChat::Whatsapp::Processor.new(self) do |config|
      config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
      config.use_session_store FlowChat::Session::CacheSessionStore
    end

    processor.run DemoRestaurantFlow, :main_page

  ensure
    # Restore original mode
    FlowChat::Config.whatsapp.message_handling_mode = original_mode
  end

  # Simulator Mode Demo (for testing)
  # Usage: GET/POST /demo/whatsapp_simulator
  def whatsapp_simulator_demo
    # Force simulator mode for testing
    original_mode = FlowChat::Config.whatsapp.message_handling_mode
    FlowChat::Config.whatsapp.message_handling_mode = :simulator

    processor = FlowChat::Whatsapp::Processor.new(self, enable_simulator: true) do |config|
      config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
      config.use_session_store FlowChat::Session::CacheSessionStore
    end

    processor.run DemoRestaurantFlow, :main_page

  ensure
    # Restore original mode
    FlowChat::Config.whatsapp.message_handling_mode = original_mode
  end
end 
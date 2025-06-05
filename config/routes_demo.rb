# Demo Routes Configuration for FlowChat Comprehensive Demo
# 
# Add these routes to your config/routes.rb file to enable the demo endpoints
# 
# Example integration:
# Rails.application.routes.draw do
#   # Your existing routes...
#   
#   # FlowChat Demo Routes
#   scope :demo do
#     post 'ussd' => 'demo#ussd_demo'
#     match 'whatsapp' => 'demo#whatsapp_demo', via: [:get, :post]
#     match 'whatsapp_custom' => 'demo#whatsapp_custom_demo', via: [:get, :post]
#     match 'whatsapp_background' => 'demo#whatsapp_background_demo', via: [:get, :post]
#     match 'whatsapp_simulator' => 'demo#whatsapp_simulator_demo', via: [:get, :post]
#   end
# end

Rails.application.routes.draw do
  # FlowChat Comprehensive Demo Routes
  scope :demo do
    # USSD Demo
    # Endpoint: POST /demo/ussd
    # Purpose: Demonstrates USSD integration with all features
    # Features: Pagination, session management, complex workflows
    post 'ussd' => 'demo#ussd_demo'

    # WhatsApp Demo (Standard)
    # Endpoint: GET/POST /demo/whatsapp  
    # Purpose: Standard WhatsApp integration with media support
    # Features: Rich media, interactive elements, buttons/lists
    match 'whatsapp' => 'demo#whatsapp_demo', via: [:get, :post]

    # WhatsApp Demo (Custom Configuration)
    # Endpoint: GET/POST /demo/whatsapp_custom
    # Purpose: Shows multi-tenant configuration capabilities
    # Features: Custom credentials, per-endpoint configuration
    match 'whatsapp_custom' => 'demo#whatsapp_custom_demo', via: [:get, :post]

    # WhatsApp Demo (Background Processing)
    # Endpoint: GET/POST /demo/whatsapp_background
    # Purpose: Demonstrates background job integration
    # Features: Asynchronous response delivery, job queuing
    match 'whatsapp_background' => 'demo#whatsapp_background_demo', via: [:get, :post]

    # WhatsApp Demo (Simulator Mode)
    # Endpoint: GET/POST /demo/whatsapp_simulator
    # Purpose: Testing mode that returns response data as JSON
    # Features: No actual WhatsApp API calls, perfect for testing
    match 'whatsapp_simulator' => 'demo#whatsapp_simulator_demo', via: [:get, :post]
  end

  # Optional: Simulator interface for testing
  # Uncomment if you want to add the simulator UI
  # get '/simulator' => 'simulator#index'
  
  # Optional: API documentation endpoint
  # get '/demo' => 'demo#index'
end 
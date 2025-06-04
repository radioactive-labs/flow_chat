# Example USSD Controller
# Add this to your Rails application as app/controllers/ussd_controller.rb

class UssdController < ApplicationController
  skip_forgery_protection

  def process_request
    processor = FlowChat::Ussd::Processor.new(self) do |config|
      config.use_gateway FlowChat::Ussd::Gateway::Nalo
      # Use Rails session for USSD (shorter sessions)
      config.use_session_store FlowChat::Session::RailsSessionStore
      
      # Enable resumable sessions (optional)
      config.use_resumable_sessions
    end

    processor.run WelcomeFlow, :main_page
  end
end

# Example Flow for USSD
# Add this to your Rails application as app/flow_chat/welcome_flow.rb

class WelcomeFlow < FlowChat::Flow
  def main_page
    # Welcome the user
    name = app.screen(:name) do |prompt|
      prompt.ask "Welcome to our service! What's your name?",
        transform: ->(input) { input.strip.titleize }
    end

    # Show main menu with numbered options (USSD style)
    choice = app.screen(:main_menu) do |prompt|
      prompt.select "Hi #{name}! Choose an option:", {
        "1" => "Account Info",
        "2" => "Make Payment", 
        "3" => "Get Balance",
        "4" => "Customer Support"
      }
    end

    case choice
    when "1"
      show_account_info
    when "2"
      make_payment
    when "3"
      get_balance
    when "4"
      customer_support
    end
  end

  private

  def show_account_info
    info_choice = app.screen(:account_info) do |prompt|
      prompt.select "Account Information:", {
        "1" => "Personal Details",
        "2" => "Account Balance",
        "3" => "Transaction History",
        "0" => "Back to Main Menu"
      }
    end

    case info_choice
    when "1"
      app.say "Name: John Doe\\nPhone: #{app.phone_number}\\nAccount: Active"
    when "2"
      app.say "Current Balance: $150.75\\nAvailable Credit: $1,000.00"
    when "3"
      app.say "Last 3 Transactions:\\n1. +$50.00 - Deposit\\n2. -$25.50 - Purchase\\n3. -$15.00 - Transfer"
    when "0"
      main_page  # Go back to main menu
    end
  end

  def make_payment
    amount = app.screen(:payment_amount) do |prompt|
      prompt.ask "Enter amount to pay:",
        convert: ->(input) { input.to_f },
        validate: ->(amount) {
          return "Amount must be greater than 0" unless amount > 0
          return "Maximum payment is $500" unless amount <= 500
          nil
        }
    end

    recipient = app.screen(:payment_recipient) do |prompt|
      prompt.ask "Enter recipient phone number:",
        validate: ->(input) {
          return "Phone number must be 10 digits" unless input.match?(/\\A\\d{10}\\z/)
          nil
        }
    end

    # Confirmation screen
    confirmed = app.screen(:payment_confirmation) do |prompt|
      prompt.yes? "Pay $#{amount} to #{recipient}?\\nConfirm payment?"
    end

    if confirmed
      # Process payment (your business logic here)
      transaction_id = process_payment(amount, recipient)
      app.say "Payment successful!\\nTransaction ID: #{transaction_id}\\nAmount: $#{amount}\\nTo: #{recipient}"
    else
      app.say "Payment cancelled"
    end
  end

  def get_balance
    # Simulate balance check
    balance = check_account_balance(app.phone_number)
    app.say "Account Balance\\n\\nAvailable: $#{balance[:available]}\\nPending: $#{balance[:pending]}\\nTotal: $#{balance[:total]}"
  end

  def customer_support
    support_choice = app.screen(:support_menu) do |prompt|
      prompt.select "Customer Support:", {
        "1" => "Report an Issue",
        "2" => "Account Questions", 
        "3" => "Technical Support",
        "4" => "Speak to Agent",
        "0" => "Main Menu"
      }
    end

    case support_choice
    when "1"
      report_issue
    when "2"
      app.say "For account questions:\\nCall: 123-456-7890\\nEmail: support@company.com\\nHours: 9AM-5PM Mon-Fri"
    when "3"
      app.say "Technical Support:\\nCall: 123-456-7891\\nEmail: tech@company.com\\n24/7 Support Available"
    when "4"
      app.say "Connecting you to an agent...\\nPlease call 123-456-7890\\nOr visit our nearest branch"
    when "0"
      main_page
    end
  end

  def report_issue
    issue_type = app.screen(:issue_type) do |prompt|
      prompt.select "Select issue type:", {
        "1" => "Payment Problem",
        "2" => "Account Access",
        "3" => "Service Error",
        "4" => "Other"
      }
    end

    description = app.screen(:issue_description) do |prompt|
      prompt.ask "Briefly describe the issue:",
        validate: ->(input) {
          return "Description must be at least 10 characters" unless input.length >= 10
          nil
        }
    end

    # Save the issue (your business logic here)
    ticket_id = create_support_ticket(issue_type, description, app.phone_number)
    
    app.say "Issue reported successfully!\\n\\nTicket ID: #{ticket_id}\\nWe'll contact you within 24 hours.\\n\\nThank you!"
  end

  # Helper methods (implement your business logic)
  
  def process_payment(amount, recipient)
    # Your payment processing logic here
    # Return transaction ID
    "TXN#{rand(100000..999999)}"
  end

  def check_account_balance(phone_number)
    # Your balance checking logic here
    {
      available: "150.75",
      pending: "25.00", 
      total: "175.75"
    }
  end

  def create_support_ticket(issue_type, description, phone_number)
    # Your ticket creation logic here
    Rails.logger.info "Support ticket created: #{issue_type} - #{description} from #{phone_number}"
    "TICKET#{rand(10000..99999)}"
  end
end

# Configuration Examples:

# 1. Basic configuration with custom pagination
class UssdController < ApplicationController
  skip_forgery_protection

  def process_request
    # Configure pagination for shorter messages
    FlowChat::Config.ussd.pagination_page_size = 120
    FlowChat::Config.ussd.pagination_next_option = "#"
    FlowChat::Config.ussd.pagination_back_option = "*"

    processor = FlowChat::Ussd::Processor.new(self) do |config|
      config.use_gateway FlowChat::Ussd::Gateway::Nalo
      config.use_session_store FlowChat::Session::RailsSessionStore
    end

    processor.run WelcomeFlow, :main_page
  end
end

# 2. Configuration with custom middleware
class LoggingMiddleware
  def initialize(app)
    @app = app
  end

  def call(context)
    Rails.logger.info "USSD Request from #{context['request.msisdn']}: #{context.input}"
    start_time = Time.current
    
    result = @app.call(context)
    
    duration = Time.current - start_time
    Rails.logger.info "USSD Response (#{duration.round(3)}s): #{result[1]}"
    
    result
  end
end

class UssdController < ApplicationController
  skip_forgery_protection

  def process_request
    processor = FlowChat::Ussd::Processor.new(self) do |config|
      config.use_gateway FlowChat::Ussd::Gateway::Nalo
      config.use_session_store FlowChat::Session::RailsSessionStore
      config.use_middleware LoggingMiddleware  # Add custom logging
      config.use_resumable_sessions           # Enable resumable sessions
    end

    processor.run WelcomeFlow, :main_page
  end
end

# 3. Configuration with cache-based sessions for longer persistence
class UssdController < ApplicationController
  skip_forgery_protection

  def process_request
    processor = FlowChat::Ussd::Processor.new(self) do |config|
      config.use_gateway FlowChat::Ussd::Gateway::Nalo
      # Use cache store for longer session persistence
      config.use_session_store FlowChat::Session::CacheSessionStore
    end

    processor.run WelcomeFlow, :main_page
  end
end

# Add this route to your config/routes.rb:
# post '/ussd', to: 'ussd#process_request'

# For Nsano gateway, use:
# config.use_gateway FlowChat::Ussd::Gateway::Nsano 
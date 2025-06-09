# Example USSD Controller
# Add this to your Rails application as app/controllers/ussd_controller.rb

class UssdController < ApplicationController
  skip_forgery_protection

  def process_request
    processor = FlowChat::Ussd::Processor.new(self) do |config|
      config.use_gateway FlowChat::Ussd::Gateway::Nalo
      # Use Rails session for USSD (shorter sessions)
      config.use_session_store FlowChat::Session::RailsSessionStore

      # Enable durable sessions (optional)
      config.use_durable_sessions  # Configures flow+platform isolation with durable sessions
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
      prompt.ask "Welcome! What's your name?",
        transform: ->(input) { input.strip.titleize }
    end

    # Show main menu with numbered options (USSD style)
    choice = app.screen(:main_menu) do |prompt|
      prompt.select "Hi #{name}! Choose:", {
        "1" => "Account Info",
        "2" => "Make Payment",
        "3" => "Get Balance",
        "4" => "Support"
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
      prompt.select "Account Info:", {
        "1" => "Personal Details",
        "2" => "Balance",
        "3" => "Transaction History",
        "0" => "Main Menu"
      }
    end

    case info_choice
    when "1"
      app.say "Name: John Doe\nPhone: #{app.phone_number}\nStatus: Active"
    when "2"
      app.say "Balance: $150.75\nCredit: $1,000.00"
    when "3"
      app.say "Recent:\n+$50.00 Deposit\n-$25.50 Purchase\n-$15.00 Transfer"
    when "0"
      main_page
    end
  end

  def make_payment
    amount = app.screen(:payment_amount) do |prompt|
      prompt.ask "Enter amount:",
        validate: ->(input) {
          amt = input.to_f
          return "Invalid amount" unless amt > 0
          return "Max $500" unless amt <= 500
          nil
        },
        transform: ->(input) { input.to_f }
    end

    recipient = app.screen(:payment_recipient) do |prompt|
      prompt.ask "Recipient phone:",
        validate: ->(input) {
          return "10 digits required" unless input.match?(/\A\d{10}\z/)
          nil
        }
    end

    # Confirmation screen
    confirmed = app.screen(:payment_confirmation) do |prompt|
      prompt.yes? "Pay $#{amount} to #{recipient}?"
    end

    if confirmed
      # Process payment (your business logic here)
      transaction_id = process_payment(amount, recipient)
      app.say "Payment successful!\nID: #{transaction_id}\nAmount: $#{amount}"
    else
      app.say "Payment cancelled"
    end
  end

  def get_balance
    # Simulate balance check
    balance = check_account_balance(app.phone_number)
    app.say "Balance\n\nAvailable: $#{balance[:available]}\nPending: $#{balance[:pending]}"
  end

  def customer_support
    support_choice = app.screen(:support_menu) do |prompt|
      prompt.select "Support:", {
        "1" => "Report Issue",
        "2" => "Contact Info",
        "0" => "Main Menu"
      }
    end

    case support_choice
    when "1"
      report_issue
    when "2"
      app.say "Support:\nCall: 123-456-7890\nEmail: support@company.com\nHours: 9AM-5PM"
    when "0"
      main_page
    end
  end

  def report_issue
    issue_type = app.screen(:issue_type) do |prompt|
      prompt.select "Issue type:", {
        "1" => "Payment Problem",
        "2" => "Account Access",
        "3" => "Service Error",
        "4" => "Other"
      }
    end

    description = app.screen(:issue_description) do |prompt|
      prompt.ask "Describe issue:",
        validate: ->(input) {
          return "Min 10 characters" if input.length < 10
          nil
        }
    end

    # Save the issue (your business logic here)
    ticket_id = create_support_ticket(issue_type, description, app.phone_number)

    app.say "Issue reported!\n\nTicket: #{ticket_id}\nWe'll contact you within 24hrs"
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
      pending: "25.00"
    }
  end

  def create_support_ticket(issue_type, description, phone_number)
    # Your ticket creation logic here
    Rails.logger.info "Ticket: #{issue_type} - #{description} from #{phone_number}"
    "TICKET#{rand(10000..99999)}"
  end
end

# Configuration Examples:

# 1. Basic configuration with custom pagination
# rubocop:disable Lint/DuplicateMethods
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
# rubocop:enable Lint/DuplicateMethods

# 2. Configuration with custom middleware
class LoggingMiddleware
  def initialize(app)
    @app = app
  end

  def call(context)
    Rails.logger.info "USSD Request from #{context["request.msisdn"]}: #{context.input}"
    start_time = Time.current

    result = @app.call(context)

    duration = Time.current - start_time
    Rails.logger.info "USSD Response (#{duration.round(3)}s): #{result[1]}"

    result
  end
end

# rubocop:disable Lint/DuplicateMethods
class UssdController < ApplicationController
  skip_forgery_protection

  def process_request
    processor = FlowChat::Ussd::Processor.new(self) do |config|
      config.use_gateway FlowChat::Ussd::Gateway::Nalo
      config.use_session_store FlowChat::Session::RailsSessionStore
      config.use_middleware LoggingMiddleware  # Add custom logging
      config.use_durable_sessions           # Enable durable sessions
      
      # Or configure session boundaries explicitly:
      # config.use_session_config(
      #   boundaries: [:flow, :platform],     # which boundaries to enforce
      #   hash_phone_numbers: true            # hash phone numbers for privacy
      # )
    end

    processor.run WelcomeFlow, :main_page
  end
end
# rubocop:enable Lint/DuplicateMethods

# 3. Configuration with cache-based sessions for longer persistence
# rubocop:disable Lint/DuplicateMethods
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
# rubocop:enable Lint/DuplicateMethods

# Add this route to your config/routes.rb:
# post '/ussd', to: 'ussd#process_request'

# For Nsano gateway, use:
# config.use_gateway FlowChat::Ussd::Gateway::Nsano

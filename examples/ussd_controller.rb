# Example USSD Controller
# Add this to your Rails application as app/controllers/ussd_controller.rb

class UssdController < ApplicationController
  skip_forgery_protection

  def process_request
    processor = FlowChat::Processor.new(self) do |config|
      config.use_gateway FlowChat::Ussd::Gateway::Nalo
      config.use_session_store FlowChat::Session::CacheSessionStore

      # Durable sessions key on the phone number, so a conversation survives the
      # telco rotating its session id on timeout. Optional.
      config.use_durable_sessions

      # Other options you can set here:
      #
      #   config.use_middleware LoggingMiddleware        # custom middleware (see below)
      #   config.use_session_config(                     # explicit session boundaries
      #     boundaries: [:flow, :platform],
      #     hash_identifiers: true                       # hash phone numbers for privacy
      #   )
    end

    processor.run UssdWelcomeFlow, :main_page
  end
end

# Add this route to your config/routes.rb:
#   post "/ussd", to: "ussd#process_request"

# Pagination is configured globally, not per processor. USSD messages are
# length-limited, so long output is split into pages with navigation options:
#
#   FlowChat::Config.ussd.pagination_page_size = 120
#   FlowChat::Config.ussd.pagination_next_option = "#"
#   FlowChat::Config.ussd.pagination_back_option = "0"

# A custom middleware, added above with config.use_middleware. It sees the
# normalized context on the way in and the [type, prompt, choices, media] result
# on the way out.
class LoggingMiddleware
  def initialize(app)
    @app = app
  end

  def call(context)
    Rails.logger.info "USSD request from #{context["request.msisdn"]}: #{context.input}"
    start_time = Time.current

    result = @app.call(context)

    duration = Time.current - start_time
    Rails.logger.info "USSD response (#{duration.round(3)}s): #{result[1]}"

    result
  end
end

# Example flow for USSD
# Add this to your Rails application as app/flow_chat/ussd_welcome_flow.rb

class UssdWelcomeFlow < FlowChat::Flow
  def main_page
    name = app.screen(:name) do |prompt|
      prompt.ask "Welcome! What's your name?",
        transform: ->(input) { input.strip.titleize }
    end

    # Choices render as a numbered list; the flow works in the choice keys.
    choice = app.screen(:main_menu) do |prompt|
      prompt.select "Hi #{name}! Choose:", {
        "info" => "Account Info",
        "payment" => "Make Payment",
        "balance" => "Get Balance",
        "support" => "Support"
      }
    end

    case choice
    when "info" then show_account_info
    when "payment" then make_payment
    when "balance" then get_balance
    when "support" then customer_support
    end
  end

  private

  def show_account_info
    info_choice = app.screen(:account_info) do |prompt|
      prompt.select "Account Info:", {
        "details" => "Personal Details",
        "balance" => "Balance",
        "history" => "Transaction History",
        "back" => "Main Menu"
      }
    end

    case info_choice
    when "details"
      app.say "Name: John Doe\nPhone: #{app.msisdn}\nStatus: Active"
    when "balance"
      app.say "Balance: $150.75\nCredit: $1,000.00"
    when "history"
      app.say "Recent:\n+$50.00 Deposit\n-$25.50 Purchase\n-$15.00 Transfer"
    when "back"
      main_page
    end
  end

  def make_payment
    amount = app.screen(:payment_amount) do |prompt|
      prompt.ask "Enter amount:",
        validate: ->(input) {
          amount = input.to_f
          next "Invalid amount" unless amount > 0
          next "Max $500" unless amount <= 500
          nil
        },
        transform: ->(input) { input.to_f }
    end

    recipient = app.screen(:payment_recipient) do |prompt|
      prompt.ask "Recipient phone:",
        validate: ->(input) { "10 digits required" unless input.match?(/\A\d{10}\z/) }
    end

    confirmed = app.screen(:payment_confirmation) do |prompt|
      prompt.yes? "Pay $#{amount} to #{recipient}?"
    end

    if confirmed
      transaction_id = process_payment(amount, recipient)
      app.say "Payment successful!\nID: #{transaction_id}\nAmount: $#{amount}"
    else
      app.say "Payment cancelled"
    end
  end

  def get_balance
    balance = check_account_balance(app.msisdn)
    app.say "Balance\n\nAvailable: $#{balance[:available]}\nPending: $#{balance[:pending]}"
  end

  def customer_support
    support_choice = app.screen(:support_menu) do |prompt|
      prompt.select "Support:", {
        "report" => "Report Issue",
        "contact" => "Contact Info",
        "back" => "Main Menu"
      }
    end

    case support_choice
    when "report"
      report_issue
    when "contact"
      app.say "Support:\nCall: 123-456-7890\nEmail: support@company.com\nHours: 9AM-5PM"
    when "back"
      main_page
    end
  end

  def report_issue
    issue_type = app.screen(:issue_type) do |prompt|
      prompt.select "Issue type:", {
        "payment" => "Payment Problem",
        "access" => "Account Access",
        "error" => "Service Error",
        "other" => "Other"
      }
    end

    description = app.screen(:issue_description) do |prompt|
      prompt.ask "Describe issue:",
        validate: ->(input) { "Min 10 characters" if input.length < 10 }
    end

    ticket_id = create_support_ticket(issue_type, description, app.msisdn)
    app.say "Issue reported!\n\nTicket: #{ticket_id}\nWe'll contact you within 24hrs"
  end

  # Replace these with your own business logic.

  def process_payment(amount, recipient)
    "TXN#{rand(100000..999999)}"
  end

  def check_account_balance(msisdn)
    {available: "150.75", pending: "25.00"}
  end

  def create_support_ticket(issue_type, description, msisdn)
    Rails.logger.info "Ticket: #{issue_type} - #{description} from #{msisdn}"
    "TICKET#{rand(10000..99999)}"
  end
end

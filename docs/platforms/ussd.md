# USSD Development with FlowChat

USSD (Unstructured Supplementary Service Data) enables interactive menu-driven applications accessible from any mobile phone. FlowChat provides comprehensive USSD support with automatic pagination, choice mapping, and session management.

## Supported USSD Gateways

FlowChat's pluggable architecture supports multiple USSD gateways:

| Gateway | Provider | Status | Features |
|---------|----------|---------|----------|
| **Nalo** | Nalo USSD Platform | ✅ Active | Pagination, choice mapping, session management |
| **Custom** | Your Implementation | 🔧 Build Your Own | Full gateway interface support |

```ruby
# Built-in Nalo gateway (included with FlowChat)
config.use_gateway FlowChat::Ussd::Gateway::Nalo

# Example custom gateway (you would build this)
config.use_gateway YourCompany::Ussd::Gateway::MTN, mtn_config
```

## Quick Start

### Basic USSD Controller

```ruby
class UssdController < ApplicationController
  skip_forgery_protection
  
  def process_request
    processor = FlowChat::Processor.new(self) do |config|
      config.use_gateway FlowChat::Ussd::Gateway::Nalo
      config.use_session_store FlowChat::Session::RailsSessionStore
      
      # USSD-optimized session configuration
      config.use_session_config(
        boundaries: [:flow, :platform],  # Isolate by flow and platform
        identifier: :msisdn              # Use phone number for sessions
      )
    end

    processor.run MenuFlow, :main_menu
  end
end
```

### Simple USSD Flow

```ruby
class MenuFlow < FlowChat::Flow
  def main_menu
    choice = app.screen(:menu) do |prompt|
      prompt.select "Welcome! Choose:", {
        "1" => "Account Balance",
        "2" => "Transfer Money", 
        "3" => "Buy Airtime",
        "4" => "Contact Support"
      }
    end

    case choice
    when "1" then show_balance
    when "2" then transfer_money
    when "3" then buy_airtime
    when "4" then show_support
    end
  end

  private

  def show_balance
    balance = get_account_balance(app.msisdn)
    app.say "Balance: UGX #{balance}\nThank you!"
  end

  def transfer_money
    recipient = app.screen(:recipient) do |prompt|
      prompt.ask "Enter recipient number:",
        validate: ->(input) {
          return "Invalid number" unless input.match?(/^0\d{9}$/)
          nil
        }
    end

    amount = app.screen(:amount) do |prompt|
      prompt.ask "Enter amount:",
        validate: ->(input) {
          amt = input.to_i
          return "Minimum UGX 500" if amt < 500
          return "Maximum UGX 1,000,000" if amt > 1_000_000
          nil
        },
        transform: ->(input) { input.to_i }
    end

    confirmed = app.screen(:confirm) do |prompt|
      prompt.yes? "Send UGX #{amount} to #{recipient}?"
    end

    if confirmed
      transfer_id = process_transfer(app.msisdn, recipient, amount)
      app.say "Transfer successful!\nID: #{transfer_id}"
    else
      app.say "Transfer cancelled"
    end
  end
end
```

## USSD-Specific Features

### Automatic Pagination

Long messages are automatically split into pages with navigation options:

```ruby
# Configuration
FlowChat::Config.ussd.pagination_page_size = 160    # Characters per page
FlowChat::Config.ussd.pagination_next_option = "#"  # Next page option
FlowChat::Config.ussd.pagination_back_option = "0"  # Previous page option

# Long content automatically paginated
def show_transaction_history
  transactions = get_user_transactions(app.msisdn)
  
  history = transactions.map.with_index(1) do |txn, i|
    "#{i}. #{txn.date} - #{txn.type}\nAmount: #{txn.amount}\nRef: #{txn.reference}"
  end.join("\n\n")

  # FlowChat automatically paginates this long content
  app.say "Transaction History:\n\n#{history}"
end
```

### Choice Mapping

USSD choices are automatically mapped between user selections and actual values:

```ruby
def product_selection
  # User sees numbered options, your code gets meaningful values
  product = app.screen(:product) do |prompt|
    prompt.select "Choose product:", {
      "airtime" => "Buy Airtime",
      "data" => "Buy Data Bundle", 
      "voice" => "Voice Bundle",
      "sms" => "SMS Bundle"
    }
  end

  # product variable contains "airtime", "data", etc.
  case product
  when "airtime" then buy_airtime_flow
  when "data" then buy_data_flow
  # ...
  end
end
```

### Session Management

USSD sessions are typically short-lived but can be configured for different behaviors:

```ruby
# Ephemeral sessions (default for USSD)
config.use_session_config(identifier: :request_id)

# Durable sessions (survive USSD timeouts)
config.use_durable_sessions  # Uses :msisdn identifier

# Custom session configuration
config.use_session_config(
  boundaries: [:flow, :platform, :gateway],  # Session isolation
  identifier: :msisdn,                       # Use phone number
  hash_identifiers: true                     # Hash for privacy
)
```

## Advanced USSD Patterns

### Multi-Step Validation

```ruby
def registration_flow
  # Phone number validation with formatting
  phone = app.screen(:phone) do |prompt|
    prompt.ask "Enter phone number:",
      validate: ->(input) {
        # Remove common prefixes/formatting
        clean = input.gsub(/[\s\-\(\)]/, '')
        clean = clean.sub(/^(\+256|256|0)/, '')
        
        return "Invalid format" unless clean.match?(/^\d{9}$/)
        nil
      },
      transform: ->(input) {
        clean = input.gsub(/[\s\-\(\)]/, '').sub(/^(\+256|256|0)/, '')
        "+256#{clean}"
      }
  end

  # Name validation
  name = app.screen(:name) do |prompt|
    prompt.ask "Enter full name:",
      validate: ->(input) {
        return "Name too short" if input.length < 2
        return "Name too long" if input.length > 50
        return "Invalid characters" unless input.match?(/^[a-zA-Z\s\.]+$/)
        nil
      },
      transform: ->(input) { input.strip.titleize }
  end

  # Create account
  account_id = create_account(phone, name)
  app.say "Welcome #{name}!\nAccount: #{account_id}"
end
```

### Conditional Menu Systems

```ruby
def main_menu
  user = get_user_profile(app.msisdn)
  
  if user.nil?
    registration_flow
  elsif user.account_status == 'suspended'
    suspended_account_menu
  elsif user.account_type == 'premium'
    premium_menu
  else
    standard_menu
  end
end

def premium_menu
  choice = app.screen(:premium_menu) do |prompt|
    prompt.select "Premium Menu:", {
      "1" => "💳 Account Balance",
      "2" => "💸 Transfer Money",
      "3" => "📱 Buy Bundles", 
      "4" => "📊 Investment Dashboard",
      "5" => "🏆 Premium Support",
      "0" => "Exit"
    }
  end
  
  # Handle premium-specific options
end

def standard_menu
  choice = app.screen(:standard_menu) do |prompt|
    prompt.select "Main Menu:", {
      "1" => "Check Balance",
      "2" => "Transfer Money",
      "3" => "Buy Airtime",
      "4" => "Support",
      "0" => "Exit"
    }
  end
end
```

### Error Handling and Recovery

```ruby
def transfer_money
  begin
    recipient = app.screen(:recipient) do |prompt|
      prompt.ask "Recipient number:",
        validate: method(:validate_phone_number)
    end

    amount = app.screen(:amount) do |prompt|
      prompt.ask "Amount (UGX):",
        validate: method(:validate_amount),
        transform: ->(input) { input.to_i }
    end

    # Check balance before confirmation
    balance = get_balance(app.msisdn)
    if amount > balance
      app.say "Insufficient funds.\nBalance: UGX #{balance}\nRequired: UGX #{amount}"
      return
    end

    confirmed = app.screen(:confirm) do |prompt|
      prompt.yes? "Send UGX #{amount} to #{recipient}?\nFee: UGX #{calculate_fee(amount)}"
    end

    if confirmed
      transfer_id = process_transfer(app.msisdn, recipient, amount)
      app.say "Transfer successful!\nRef: #{transfer_id}\nNew balance: UGX #{get_balance(app.msisdn)}"
    else
      app.say "Transfer cancelled"
    end

  rescue InsufficientFundsError => e
    app.say "Transfer failed: Insufficient funds"
  rescue NetworkError => e
    app.say "Network error. Please try again.\nRef: #{SecureRandom.hex(4)}"
  rescue => e
    Rails.logger.error "Transfer error: #{e.message}"
    app.say "Service temporarily unavailable.\nPlease try again later."
  end
end

private

def validate_phone_number(input)
  # Normalize input
  clean = input.gsub(/[\s\-\(\)]/, '')
  clean = clean.sub(/^(\+256|256|0)/, '')
  
  return "Enter 9 digits" unless clean.match?(/^\d{9}$/)
  return "Cannot send to yourself" if "+256#{clean}" == app.msisdn
  nil
end

def validate_amount(input)
  amount = input.to_i
  return "Enter numbers only" if amount == 0 && input != "0"
  return "Minimum UGX 500" if amount < 500
  return "Maximum UGX 2,000,000" if amount > 2_000_000
  nil
end
```

### Back Navigation

```ruby
def multi_level_menu
  main_choice = app.screen(:main) do |prompt|
    prompt.select "Main Menu:", {
      "1" => "Financial Services",
      "2" => "Lifestyle Services", 
      "3" => "Account Settings",
      "0" => "Exit"
    }
  end

  case main_choice
  when "1"
    financial_services_menu
  when "2"
    lifestyle_services_menu
  when "3"
    account_settings_menu
  when "0"
    app.say "Thank you for using our service!"
  end
end

def financial_services_menu
  choice = app.screen(:financial) do |prompt|
    prompt.select "Financial Services:", {
      "1" => "Transfer Money",
      "2" => "Pay Bills",
      "3" => "Savings Account",
      "9" => "Back to Main Menu",
      "0" => "Exit"
    }
  end

  case choice
  when "1" then transfer_money
  when "2" then pay_bills
  when "3" then savings_menu
  when "9" 
    # Clear current screen and go back
    app.session.delete(:financial)
    multi_level_menu
  when "0"
    app.say "Thank you!"
  end
end

# Alternative: Use app.go_back for automatic navigation
def with_go_back
  if user_wants_to_go_back?
    app.go_back  # Automatically handles navigation stack
  end
end
```

## USSD Configuration

### Global USSD Settings

```ruby
# config/initializers/flow_chat.rb
FlowChat::Config.ussd.pagination_page_size = 140      # SMS character limit
FlowChat::Config.ussd.pagination_next_option = "#"    # Next page key
FlowChat::Config.ussd.pagination_back_option = "0"    # Previous page key
FlowChat::Config.ussd.pagination_next_text = "More"   # Next page text
FlowChat::Config.ussd.pagination_back_text = "Back"   # Previous page text

# Validation settings
FlowChat::Config.combine_validation_error_with_message = true  # Show original + error
```

### Per-Request Configuration

```ruby
def process_request
  # Configure pagination based on network
  network = detect_network(request)
  
  case network
  when :mtn
    FlowChat::Config.ussd.pagination_page_size = 160
  when :airtel
    FlowChat::Config.ussd.pagination_page_size = 140
  when :africel
    FlowChat::Config.ussd.pagination_page_size = 120
  end

  processor = FlowChat::Processor.new(self) do |config|
    config.use_gateway FlowChat::Ussd::Gateway::Nalo
    config.use_session_store FlowChat::Session::RailsSessionStore
  end

  processor.run MenuFlow, :main_menu
end
```

## Testing USSD Applications

### Using the Simulator

```ruby
# In rails console or test
simulator = FlowChat::Simulator.new(MenuFlow, :main_menu)

# Simulate USSD session
simulator.start
# => "Welcome! Choose:\n1. Account Balance\n2. Transfer Money\n..."

simulator.send_message("2")  # Select transfer money
# => "Enter recipient number:"

simulator.send_message("0701234567")
# => "Enter amount:"

simulator.send_message("5000")
# => "Send UGX 5000 to 0701234567?\n1. Yes\n2. No"

simulator.send_message("1")  # Confirm
# => "Transfer successful!\nRef: TXN123456"
```

### Integration Testing

```ruby
# test/integration/ussd_flow_test.rb
class UssdFlowTest < ActionDispatch::IntegrationTest
  def test_complete_transfer_flow
    # Simulate Nalo USSD webhook
    post ussd_path, params: {
      msisdn: "256701234567",
      text: "",
      session_id: "test_session_123"
    }

    assert_response :success
    assert_includes response.body, "Welcome! Choose:"

    # Select transfer money
    post ussd_path, params: {
      msisdn: "256701234567", 
      text: "2",
      session_id: "test_session_123"
    }

    assert_includes response.body, "Enter recipient number:"

    # Continue flow...
  end
end
```

## Network-Specific Considerations

### Character Limits

Different networks have different USSD character limits:

```ruby
NETWORK_LIMITS = {
  mtn: 160,
  airtel: 140, 
  africel: 120,
  utl: 140
}.freeze

def adjust_pagination_for_network(network)
  limit = NETWORK_LIMITS[network] || 140
  FlowChat::Config.ussd.pagination_page_size = limit
end
```

### Network-Specific Features

```ruby
def network_aware_menu
  network = detect_network(app.msisdn)
  
  base_options = {
    "1" => "Check Balance",
    "2" => "Transfer Money", 
    "3" => "Buy Airtime"
  }

  # Add network-specific options
  case network
  when :mtn
    base_options["4"] = "MTN Mobile Money"
    base_options["5"] = "MTN Packages"
  when :airtel
    base_options["4"] = "Airtel Money"
    base_options["5"] = "Airtel Packages"
  end

  choice = app.screen(:network_menu) do |prompt|
    prompt.select "Services:", base_options
  end

  handle_choice(choice, network)
end
```

## Performance Optimization

### Efficient Database Queries

```ruby
def show_transaction_history
  # Efficient pagination for large datasets
  page_size = 5
  offset = (current_page - 1) * page_size
  
  transactions = Transaction
    .where(msisdn: app.msisdn)
    .order(created_at: :desc)
    .limit(page_size)
    .offset(offset)
    .pluck(:date, :type, :amount, :reference)

  if transactions.empty?
    app.say "No transactions found"
    return
  end

  history = transactions.map.with_index(offset + 1) do |(date, type, amount, ref), i|
    "#{i}. #{date.strftime('%d/%m')} #{type}\nUGX #{amount}\n#{ref}"
  end.join("\n\n")

  app.say "Transactions:\n#{history}"
end
```

### Caching Strategies

```ruby
def get_exchange_rates
  # Cache exchange rates for 1 hour
  Rails.cache.fetch("exchange_rates", expires_in: 1.hour) do
    fetch_exchange_rates_from_api
  end
end

def get_user_profile(msisdn)
  # Cache user profile for session duration
  app.session.get("user_profile") || begin
    profile = User.find_by(msisdn: msisdn)
    app.session.set("user_profile", profile)
    profile
  end
end
```

## Security Best Practices

### Input Sanitization

```ruby
def secure_input_handling
  # Always validate and sanitize input
  amount = app.screen(:amount) do |prompt|
    prompt.ask "Enter amount:",
      validate: ->(input) {
        # Remove any non-numeric characters
        clean = input.gsub(/[^\d]/, '')
        return "Enter numbers only" if clean.empty?
        
        amount = clean.to_i
        return "Amount too small" if amount < 100
        return "Amount too large" if amount > 10_000_000
        nil
      },
      transform: ->(input) { input.gsub(/[^\d]/, '').to_i }
  end
end
```

### Session Security

```ruby
# Hash sensitive identifiers
config.use_session_config(
  identifier: :msisdn,
  hash_identifiers: true  # Phone numbers are hashed
)

# Implement session timeouts
class SecureSessionStore < FlowChat::Session::RailsSessionStore
  def get(key)
    data = super
    if data && session_expired?
      delete_all_session_data
      return nil
    end
    data
  end

  private

  def session_expired?
    last_activity = @context.session.get("last_activity")
    return true unless last_activity
    
    Time.current - Time.parse(last_activity) > 10.minutes
  end
end
```

## Troubleshooting

### Common USSD Issues

1. **Session Loss**
   ```ruby
   # Use durable sessions for longer flows
   config.use_durable_sessions
   
   # Or implement session recovery
   def recover_session
     if app.session.get(:current_screen).nil?
       # Restart from main menu
       main_menu
     end
   end
   ```

2. **Character Encoding**
   ```ruby
   # Ensure proper encoding for special characters
   def safe_message(text)
     text.encode('UTF-8', invalid: :replace, undef: :replace)
   end
   ```

3. **Timeout Handling**
   ```ruby
   def handle_timeout
     app.say "Session timeout.\nDial *123# to continue"
   rescue FlowChat::Interrupt::SessionTimeout
     handle_timeout
   end
   ```

### Debugging

Enable detailed logging:

```ruby
# config/initializers/flow_chat.rb
FlowChat::Config.logger.level = Logger::DEBUG

# In your flow
Rails.logger.debug "USSD Debug - Screen: #{app.navigation_stack.last}"
Rails.logger.debug "USSD Debug - Input: #{app.input.inspect}"
Rails.logger.debug "USSD Debug - Session: #{app.session.inspect}"
```

## Next Steps

- **[Gateway Development](../gateway-development.md)** - Build custom USSD gateways
- **[Session Management](../session-management.md)** - Advanced session configuration
- **[Multi-Platform Development](multi-platform.md)** - Share flows across platforms 

See the complete USSD documentation for advanced patterns, configuration options, and best practices. 
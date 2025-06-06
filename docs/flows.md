# Flow Development Guide

This guide covers advanced flow patterns, validation techniques, and best practices for building sophisticated conversational workflows.

## Flow Architecture

### Flow Lifecycle

Every flow method must result in user interaction:

```ruby
class ExampleFlow < FlowChat::Flow
  def main_page
    # ✅ Always end with user interaction
    choice = app.screen(:choice) { |p| p.select "Choose:", ["A", "B"] }
    
    case choice
    when "A"
      handle_option_a
      app.say "Option A completed!"  # Required interaction
    when "B"  
      handle_option_b
      app.say "Option B completed!"  # Required interaction
    end
  end
end
```

### Session Management

FlowChat automatically persists screen results:

```ruby
class RegistrationFlow < FlowChat::Flow
  def main_page
    # These values persist across requests
    name = app.screen(:name) { |p| p.ask "Name?" }
    email = app.screen(:email) { |p| p.ask "Email?" }
    
    # Show summary using cached values
    confirmed = app.screen(:confirm) do |prompt|
      prompt.yes? "Create account for #{name} (#{email})?"
    end
    
    if confirmed
      create_user(name: name, email: email)
      app.say "Account created!"
    end
  end
end
```

## Input Validation Patterns

### Basic Validation

```ruby
age = app.screen(:age) do |prompt|
  prompt.ask "Enter your age:",
    validate: ->(input) { 
      return "Age must be a number" unless input.match?(/^\d+$/)
      return "Must be 18 or older" unless input.to_i >= 18
      nil  # Return nil for valid input
    },
    transform: ->(input) { input.to_i }
end
```

### Complex Validation

```ruby
phone = app.screen(:phone) do |prompt|
  prompt.ask "Enter phone number:",
    validate: ->(input) {
      clean = input.gsub(/[\s\-\(\)]/, '')
      return "Invalid format" unless clean.match?(/^\+?[\d]{10,15}$/)
      return "Must start with country code" unless clean.start_with?('+')
      nil
    },
    transform: ->(input) { input.gsub(/[\s\-\(\)]/, '') }
end
```

### Conditional Validation

```ruby
class PaymentFlow < FlowChat::Flow
  def collect_payment_method
    method = app.screen(:method) do |prompt|
      prompt.select "Payment method:", ["card", "mobile_money"]
    end
    
    if method == "card"
      collect_card_details
    else
      collect_mobile_money_details
    end
  end
  
  private
  
  def collect_card_details
    card = app.screen(:card) do |prompt|
      prompt.ask "Card number (16 digits):",
        validate: ->(input) {
          clean = input.gsub(/\s/, '')
          return "Must be 16 digits" unless clean.length == 16
          return "Invalid card number" unless luhn_valid?(clean)
          nil
        }
    end
    
    app.say "Card ending in #{card[-4..-1]} saved."
  end
end
```

## Menu Patterns

### Dynamic Menus

```ruby
def show_products
  products = fetch_available_products
  
  choice = app.screen(:product) do |prompt|
    prompt.select "Choose product:", products.map(&:name)
  end
  
  selected_product = products.find { |p| p.name == choice }
  show_product_details(selected_product)
end
```

### Nested Menus

```ruby
def main_menu
  choice = app.screen(:main) do |prompt|
    prompt.select "Main Menu:", {
      "products" => "View Products",
      "orders" => "My Orders", 
      "support" => "Customer Support"
    }
  end
  
  case choice
  when "products"
    products_menu
  when "orders"
    orders_menu
  when "support"
    support_menu
  end
end
```

## Advanced Patterns

### Multi-Step Forms

```ruby
class CompleteProfileFlow < FlowChat::Flow
  def main_page
    collect_basic_info
    collect_preferences
    confirm_and_save
  end
  
  private
  
  def collect_basic_info
    app.screen(:name) { |p| p.ask "Full name:" }
    app.screen(:email) { |p| p.ask "Email:" }
    app.screen(:phone) { |p| p.ask "Phone:" }
  end
  
  def collect_preferences
    app.screen(:language) { |p| p.select "Language:", ["English", "French"] }
    app.screen(:notifications) { |p| p.yes? "Enable notifications?" }
  end
  
  def confirm_and_save
    summary = build_summary
    confirmed = app.screen(:confirm) { |p| p.yes? "Save profile?\n\n#{summary}" }
    
    if confirmed
      save_profile
      app.say "Profile saved successfully!"
    else
      app.say "Profile not saved."
    end
  end
end
```

### Error Recovery

```ruby
def process_payment
  begin
    amount = app.screen(:amount) do |prompt|
      prompt.ask "Amount to pay:",
        validate: ->(input) {
          return "Invalid amount" unless input.match?(/^\d+(\.\d{2})?$/)
          return "Minimum $1.00" unless input.to_f >= 1.0
          nil
        },
        transform: ->(input) { input.to_f }
    end
    
    process_transaction(amount)
    app.say "Payment of $#{amount} processed successfully!"
    
  rescue PaymentError => e
    app.say "Payment failed: #{e.message}. Please try again."
    process_payment  # Retry
  end
end
```

## Cross-Platform Considerations

### Platform Detection

```ruby
def show_help
  if app.context["request.gateway"] == :whatsapp_cloud_api
    # WhatsApp users get rich media
    app.say "Here's how to use our service:",
      media: { type: :image, url: "https://example.com/help.jpg" }
  else
    # USSD users get text with link
    app.say "Help guide: https://example.com/help"
  end
end
```

### Progressive Enhancement

```ruby
def collect_feedback
  rating = app.screen(:rating) do |prompt|
    if whatsapp?
      # Rich interactive buttons for WhatsApp
      prompt.select "Rate our service:", {
        "5" => "⭐⭐⭐⭐⭐ Excellent",
        "4" => "⭐⭐⭐⭐ Good", 
        "3" => "⭐⭐⭐ Average",
        "2" => "⭐⭐ Poor",
        "1" => "⭐ Very Poor"
      }
    else
      # Simple numbered list for USSD
      prompt.select "Rate our service (1-5):", ["1", "2", "3", "4", "5"]
    end
  end
  
  app.say "Thank you for rating us #{rating} stars!"
end

private

def whatsapp?
  app.context["request.gateway"] == :whatsapp_cloud_api
end
```

## Best Practices

### Keep Methods Focused

```ruby
# ✅ Good: Single responsibility
def collect_contact_info
  name = app.screen(:name) { |p| p.ask "Name:" }
  email = app.screen(:email) { |p| p.ask "Email:" }
  { name: name, email: email }
end

# ❌ Avoid: Too much in one method
def handle_everything
  # 50+ lines of mixed logic
end
```

### Use Meaningful Screen Names

```ruby
# ✅ Good: Descriptive names
app.screen(:billing_address) { |p| p.ask "Billing address:" }
app.screen(:confirm_payment) { |p| p.yes? "Confirm $#{amount}?" }

# ❌ Avoid: Generic names  
app.screen(:input1) { |p| p.ask "Address:" }
app.screen(:confirm) { |p| p.yes? "OK?" }
```

### Handle Edge Cases

```ruby
def show_order_history
  orders = fetch_user_orders
  
  if orders.empty?
    app.say "You have no previous orders."
    return
  end
  
  choice = app.screen(:order) do |prompt|
    prompt.select "Select order:", orders.map(&:display_name)
  end
  
  show_order_details(orders.find { |o| o.display_name == choice })
end
```

## Testing Flows

See [Testing Guide](testing.md) for comprehensive testing strategies. 
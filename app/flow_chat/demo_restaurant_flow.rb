# FlowChat Comprehensive Demo: Restaurant Ordering System
# This flow demonstrates all major FlowChat features:
# - Cross-platform compatibility (USSD + WhatsApp)
# - Media support with graceful degradation
# - Input validation and transformation
# - Complex menu selection (arrays, hashes, large lists)
# - Session state management
# - Error handling and validation
# - Platform-specific features with fallbacks
# - Rich interactive elements

class DemoRestaurantFlow < FlowChat::Flow
  def main_page
    # Welcome with media (logo)
    app.say "🍽️ Welcome to FlowChat Restaurant!", 
      media: {
        type: :image,
        url: "https://flowchat-demo.com/restaurant-logo.jpg"
      }

    # Check if returning customer
    returning_customer = check_returning_customer

    if returning_customer
      name = app.session.get(:customer_name)
      app.say "Welcome back, #{name}! 😊"
      main_menu
    else
      customer_registration
    end
  end

  private

  def check_returning_customer
    # Check if we have customer data in session
    app.session.get(:customer_name).present?
  end

  def customer_registration
    app.say "Let's get you registered! 📝"

    # Name with transformation
    name = app.screen(:customer_name) do |prompt|
      prompt.ask "What's your name?",
        transform: ->(input) { input.strip.titleize },
        validate: ->(input) { 
          return "Name must be at least 2 characters" if input.length < 2
          return "Name can't be longer than 50 characters" if input.length > 50
          return "Name can only contain letters and spaces" unless input.match?(/\A[a-zA-Z\s]+\z/)
          nil
        }
    end

    # Phone number with validation (international format)
    phone = app.screen(:customer_phone) do |prompt|
      prompt.ask "Enter your phone number (e.g., +1234567890):",
        transform: ->(input) { input.strip.gsub(/[\s\-\(\)]/, '') },
        validate: ->(input) {
          return "Phone number must start with +" unless input.start_with?('+')
          return "Phone number must be 8-15 digits after +" unless input[1..-1].match?(/\A\d{8,15}\z/)
          nil
        }
    end

    # Age with conversion and validation
    age = app.screen(:customer_age) do |prompt|
      prompt.ask "How old are you?",
        convert: ->(input) { input.to_i },
        validate: ->(age) {
          return "You must be at least 13 to order" if age < 13
          return "Age must be reasonable (under 120)" if age > 120
          nil
        }
    end

    # Dietary preferences with hash-based selection
    dietary_preference = app.screen(:dietary_preference) do |prompt|
      prompt.select "Any dietary preferences?", {
        "none" => "No restrictions",
        "vegetarian" => "Vegetarian",
        "vegan" => "Vegan", 
        "gluten_free" => "Gluten-free",
        "keto" => "Keto",
        "halal" => "Halal"
      }
    end

    # Store customer data
    customer_data = {
      name: name,
      phone: phone,
      age: age,
      dietary_preference: dietary_preference,
      registered_at: Time.current.iso8601
    }

    app.session.set(:customer_data, customer_data)

    app.say "Thanks for registering, #{name}! 🎉", 
      media: {
        type: :sticker,
        url: "https://flowchat-demo.com/welcome-sticker.webp"
      }

    main_menu
  end

  def main_menu
    choice = app.screen(:main_menu) do |prompt|
      prompt.select "What would you like to do?", [
        "Browse Menu",
        "View Cart", 
        "Order History",
        "Account Settings",
        "Contact Support"
      ]
    end

    case choice
    when "Browse Menu"
      browse_menu
    when "View Cart"
      view_cart
    when "Order History"
      order_history
    when "Account Settings" 
      account_settings
    when "Contact Support"
      contact_support
    end
  end

  def browse_menu
    app.say "Here's our delicious menu! 📋",
      media: {
        type: :image,
        url: "https://flowchat-demo.com/menu-hero.jpg"
      }

    category = app.screen(:menu_category) do |prompt|
      prompt.select "Choose a category:", {
        "appetizers" => "🥗 Appetizers",
        "mains" => "🍽️ Main Courses", 
        "desserts" => "🍰 Desserts",
        "beverages" => "🥤 Beverages",
        "specials" => "⭐ Today's Specials"
      }
    end

    show_category_items(category)
  end

  def show_category_items(category)
    items = get_menu_items(category)
    
    app.say "#{category.titleize} Menu:",
      media: {
        type: :image,
        url: "https://flowchat-demo.com/categories/#{category}.jpg"
      }

    # Large list selection to test pagination on USSD
    item_choice = app.screen("#{category}_selection".to_sym) do |prompt|
      prompt.select "Choose an item:", items
    end

    show_item_details(category, item_choice)
  end

  def get_menu_items(category)
    # Simulate menu items (large list to test pagination)
    case category
    when "appetizers"
      {
        "caesar_salad" => "Caesar Salad - $12",
        "bruschetta" => "Bruschetta - $8", 
        "calamari" => "Fried Calamari - $14",
        "wings" => "Buffalo Wings - $10",
        "nachos" => "Loaded Nachos - $11",
        "shrimp_cocktail" => "Shrimp Cocktail - $16",
        "cheese_board" => "Artisan Cheese Board - $18",
        "soup" => "Soup of the Day - $7"
      }
    when "mains"
      # Large list to test USSD pagination
      items = {}
      dishes = [
        "Grilled Salmon", "Ribeye Steak", "Chicken Parmesan", "Lobster Tail",
        "Lamb Chops", "Fish Tacos", "Beef Stroganoff", "Chicken Alfredo",
        "Pork Tenderloin", "Seafood Paella", "Duck Confit", "Vegetarian Lasagna",
        "BBQ Ribs", "Fish & Chips", "Stuffed Peppers", "Beef Wellington"
      ]
      dishes.each_with_index do |dish, index|
        price = 18 + (index * 2)
        items["dish_#{index}"] = "#{dish} - $#{price}"
      end
      items
    when "desserts"
      {
        "tiramisu" => "Tiramisu - $8",
        "cheesecake" => "New York Cheesecake - $7",
        "chocolate_cake" => "Chocolate Lava Cake - $9",
        "ice_cream" => "Artisan Ice Cream - $6"
      }
    when "beverages"
      {
        "wine_red" => "House Red Wine - $8",
        "wine_white" => "House White Wine - $8",
        "beer" => "Craft Beer - $6",
        "cocktail" => "Signature Cocktail - $12",
        "coffee" => "Espresso Coffee - $4",
        "tea" => "Premium Tea - $3",
        "juice" => "Fresh Juice - $5",
        "soda" => "Soft Drinks - $3"
      }
    when "specials"
      {
        "special_1" => "Chef's Special Pasta - $22",
        "special_2" => "Today's Catch - Market Price",
        "special_3" => "Tasting Menu (5 courses) - $65"
      }
    else
      {}
    end
  end

  def show_item_details(category, item_key)
    item_name = get_menu_items(category)[item_key]
    
    app.say "You selected: #{item_name}",
      media: {
        type: :image,
        url: "https://flowchat-demo.com/items/#{item_key}.jpg"
      }

    # Show detailed description with document menu
    show_detailed_info = app.screen("#{item_key}_details".to_sym) do |prompt|
      prompt.yes? "Would you like to see detailed nutritional information?"
    end

    if show_detailed_info
      app.say "Here's the detailed information:",
        media: {
          type: :document,
          url: "https://flowchat-demo.com/nutrition/#{item_key}.pdf",
          filename: "#{item_key}_nutrition.pdf"
        }
    end

    # Quantity selection
    quantity = app.screen("#{item_key}_quantity".to_sym) do |prompt|
      prompt.ask "How many would you like?",
        convert: ->(input) { input.to_i },
        validate: ->(qty) {
          return "Quantity must be at least 1" if qty < 1
          return "Maximum 10 items per order" if qty > 10
          nil
        }
    end

    # Special instructions
    special_instructions = app.screen("#{item_key}_instructions".to_sym) do |prompt|
      prompt.ask "Any special instructions? (or type 'none')",
        transform: ->(input) { input.strip.downcase == 'none' ? nil : input.strip }
    end

    # Add to cart
    add_to_cart(item_key, item_name, quantity, special_instructions)

    # Continue shopping?
    continue_shopping = app.screen(:continue_shopping) do |prompt|
      prompt.yes? "Item added to cart! Continue shopping?"
    end

    if continue_shopping
      browse_menu
    else
      view_cart
    end
  end

  def add_to_cart(item_key, item_name, quantity, instructions)
    cart = app.session.get(:cart) || []
    
    cart_item = {
      key: item_key,
      name: item_name,
      quantity: quantity,
      instructions: instructions,
      added_at: Time.current.iso8601
    }
    
    cart << cart_item
    app.session.set(:cart, cart)
  end

  def view_cart
    cart = app.session.get(:cart) || []
    
    if cart.empty?
      app.say "Your cart is empty! 🛒"
      
      browse_now = app.screen(:browse_from_empty_cart) do |prompt|
        prompt.yes? "Would you like to browse our menu?"
      end
      
      if browse_now
        browse_menu
      else
        main_menu
      end
      return
    end

    # Show cart contents
    cart_summary = build_cart_summary(cart)
    app.say "Your Cart:\n\n#{cart_summary}"

    # Cart actions
    action = app.screen(:cart_action) do |prompt|
      prompt.select "What would you like to do?", [
        "Proceed to Checkout",
        "Continue Shopping", 
        "Clear Cart",
        "Remove Item"
      ]
    end

    case action
    when "Proceed to Checkout"
      checkout_process
    when "Continue Shopping"
      browse_menu
    when "Clear Cart"
      clear_cart
    when "Remove Item"
      remove_item_from_cart
    end
  end

  def build_cart_summary(cart)
    total = 0
    summary = cart.map.with_index do |item, index|
      # Extract price from item name (simplified)
      price_match = item[:name].match(/\$(\d+)/)
      price = price_match ? price_match[1].to_f : 0
      item_total = price * item[:quantity]
      total += item_total
      
      instructions_text = item[:instructions] ? "\n   Special: #{item[:instructions]}" : ""
      "#{index + 1}. #{item[:name]} x#{item[:quantity]} = $#{item_total}#{instructions_text}"
    end.join("\n")
    
    summary + "\n\nTotal: $#{total.round(2)}"
  end

  def checkout_process
    cart = app.session.get(:cart)
    customer_data = app.session.get(:customer_data)
    
    # Delivery or pickup
    order_type = app.screen(:order_type) do |prompt|
      prompt.select "How would you like your order?", {
        "delivery" => "🚚 Delivery",
        "pickup" => "🏃 Pickup"
      }
    end

    if order_type == "delivery"
      handle_delivery_address
    else
      handle_pickup_time
    end

    # Payment method
    payment_method = app.screen(:payment_method) do |prompt|
      prompt.select "Payment method:", {
        "card" => "💳 Credit/Debit Card",
        "cash" => "💵 Cash", 
        "mobile" => "📱 Mobile Payment"
      }
    end

    if payment_method == "card"
      handle_card_payment
    end

    # Order confirmation
    order_confirmation
  end

  def handle_delivery_address
    address = app.screen(:delivery_address) do |prompt|
      prompt.ask "Enter your delivery address:",
        validate: ->(addr) {
          return "Address must be at least 10 characters" if addr.length < 10
          nil
        }
    end

    # Delivery time
    delivery_time = app.screen(:delivery_time) do |prompt|
      prompt.select "Preferred delivery time:", [
        "ASAP (45-60 mins)",
        "1-2 hours",
        "2-3 hours", 
        "This evening",
        "Schedule for later"
      ]
    end

    app.session.set(:delivery_info, {
      type: "delivery",
      address: address,
      time: delivery_time
    })
  end

  def handle_pickup_time
    pickup_time = app.screen(:pickup_time) do |prompt|
      prompt.select "When would you like to pick up?", [
        "20-30 minutes",
        "30-45 minutes",
        "1 hour",
        "Schedule for later"
      ]
    end

    app.session.set(:delivery_info, {
      type: "pickup", 
      time: pickup_time
    })
  end

  def handle_card_payment
    # Card number validation (simplified for demo)
    card_number = app.screen(:card_number) do |prompt|
      prompt.ask "Enter card number (16 digits):",
        transform: ->(input) { input.gsub(/\s/, '') },
        validate: ->(card) {
          return "Card number must be 16 digits" unless card.match?(/\A\d{16}\z/)
          return "Invalid card number" unless luhn_valid?(card)
          nil
        }
    end

    # Expiry date
    expiry = app.screen(:card_expiry) do |prompt|
      prompt.ask "Expiry date (MM/YY):",
        validate: ->(exp) {
          return "Format must be MM/YY" unless exp.match?(/\A\d{2}\/\d{2}\z/)
          month, year = exp.split('/').map(&:to_i)
          return "Invalid month" unless (1..12).include?(month)
          return "Card expired" if (2000 + year) < Date.current.year
          nil
        }
    end

    # CVV
    cvv = app.screen(:card_cvv) do |prompt|
      prompt.ask "CVV (3 digits):",
        validate: ->(cvv) {
          return "CVV must be 3 digits" unless cvv.match?(/\A\d{3}\z/)
          nil
        }
    end

    app.session.set(:payment_info, {
      method: "card",
      card_last_four: card_number[-4..-1],
      status: "processed"
    })
  end

  def order_confirmation
    order_id = generate_order_id
    cart = app.session.get(:cart)
    customer_data = app.session.get(:customer_data)
    delivery_info = app.session.get(:delivery_info)
    payment_info = app.session.get(:payment_info)

    # Save order
    order_data = {
      id: order_id,
      customer: customer_data,
      items: cart,
      delivery: delivery_info,
      payment: payment_info,
      status: "confirmed",
      created_at: Time.current.iso8601
    }

    orders = app.session.get(:orders) || []
    orders << order_data
    app.session.set(:orders, orders)

    # Clear cart
    app.session.set(:cart, [])

    # Confirmation message with receipt
    app.say "🎉 Order Confirmed!\n\nOrder ##{order_id}\nThank you, #{customer_data[:name]}!",
      media: {
        type: :document,
        url: "https://flowchat-demo.com/receipts/#{order_id}.pdf",
        filename: "receipt_#{order_id}.pdf"
      }

    # Send tracking info via audio message (WhatsApp feature)
    app.say "Here's your order tracking information:",
      media: {
        type: :audio,
        url: "https://flowchat-demo.com/tracking/#{order_id}.mp3"
      }

    # Ask for feedback
    feedback_now = app.screen(:feedback_prompt) do |prompt|
      prompt.yes? "Would you like to provide feedback about your ordering experience?"
    end

    if feedback_now
      collect_feedback
    else
      post_order_options
    end
  end

  def collect_feedback
    rating = app.screen(:feedback_rating) do |prompt|
      prompt.select "How would you rate your experience?", {
        "5" => "⭐⭐⭐⭐⭐ Excellent",
        "4" => "⭐⭐⭐⭐ Good", 
        "3" => "⭐⭐⭐ Average",
        "2" => "⭐⭐ Poor",
        "1" => "⭐ Very Poor"
      }
    end

    if rating.to_i >= 4
      app.say "Thank you for the great rating! 😊"
    else
      # Collect detailed feedback for lower ratings
      feedback_details = app.screen(:feedback_details) do |prompt|
        prompt.ask "We're sorry to hear that. Could you tell us what went wrong?",
          validate: ->(feedback) {
            return "Feedback must be at least 10 characters" if feedback.length < 10
            nil
          }
      end

      app.say "Thank you for your feedback. We'll use it to improve! 🙏"
    end

    post_order_options
  end

  def post_order_options
    action = app.screen(:post_order_action) do |prompt|
      prompt.select "What would you like to do now?", [
        "Track Order",
        "Order Again", 
        "Browse Menu",
        "Contact Support",
        "Exit"
      ]
    end

    case action
    when "Track Order"
      track_order
    when "Order Again"
      browse_menu
    when "Browse Menu"
      browse_menu
    when "Contact Support"
      contact_support
    when "Exit"
      app.say "Thank you for choosing FlowChat Restaurant! 👋"
    end
  end

  def order_history
    orders = app.session.get(:orders) || []
    
    if orders.empty?
      app.say "No previous orders found."
      main_menu
      return
    end

    order_list = orders.map.with_index do |order, index|
      "#{index + 1}. Order ##{order[:id]} - #{order[:created_at]}"
    end

    selected_index = app.screen(:order_history_selection) do |prompt|
      prompt.select "Select an order to view:", order_list.map.with_index { |order, i| [i, order] }.to_h
    end

    show_order_details(orders[selected_index])
  end

  def show_order_details(order)
    details = "Order ##{order[:id]}\n"
    details += "Status: #{order[:status].titleize}\n"
    details += "Date: #{order[:created_at]}\n\n"
    details += "Items:\n"
    
    order[:items].each do |item|
      details += "- #{item[:name]} x#{item[:quantity]}\n"
    end

    app.say details

    action = app.screen(:order_detail_action) do |prompt|
      prompt.select "What would you like to do?", [
        "Track Order",
        "Reorder Items",
        "Contact Support",
        "Back to Menu"
      ]
    end

    case action
    when "Track Order"
      track_order(order[:id])
    when "Reorder Items"
      reorder_items(order[:items])
    when "Contact Support"
      contact_support
    when "Back to Menu"
      main_menu
    end
  end

  def track_order(order_id = nil)
    order_id ||= app.session.get(:orders)&.last&.dig(:id)
    
    if order_id.nil?
      app.say "No orders to track."
      main_menu
      return
    end

    # Simulate tracking with video
    app.say "Here's your order tracking:",
      media: {
        type: :video,
        url: "https://flowchat-demo.com/tracking/#{order_id}.mp4"
      }

    app.say "📍 Order ##{order_id}\n🕐 Estimated time: 25 minutes\n📍 Status: Being prepared"
    
    main_menu
  end

  def account_settings
    customer_data = app.session.get(:customer_data)
    
    setting = app.screen(:account_setting) do |prompt|
      prompt.select "Account Settings:", [
        "Update Name",
        "Update Phone", 
        "Change Dietary Preferences",
        "View Account Info",
        "Delete Account"
      ]
    end

    case setting
    when "Update Name"
      update_customer_name
    when "Update Phone"
      update_customer_phone
    when "Change Dietary Preferences"
      update_dietary_preferences
    when "View Account Info"
      show_account_info
    when "Delete Account"
      delete_account
    end
  end

  def update_customer_name
    new_name = app.screen(:update_name) do |prompt|
      prompt.ask "Enter your new name:",
        transform: ->(input) { input.strip.titleize },
        validate: ->(input) { 
          return "Name must be at least 2 characters" if input.length < 2
          nil
        }
    end

    customer_data = app.session.get(:customer_data)
    customer_data[:name] = new_name
    app.session.set(:customer_data, customer_data)

    app.say "Name updated successfully! ✅"
    account_settings
  end

  def contact_support
    issue_type = app.screen(:support_issue_type) do |prompt|
      prompt.select "What can we help you with?", {
        "order_issue" => "Order Issue",
        "payment_problem" => "Payment Problem", 
        "delivery_issue" => "Delivery Issue",
        "food_quality" => "Food Quality Concern",
        "technical_support" => "Technical Support",
        "general_inquiry" => "General Inquiry"
      }
    end

    # Collect issue description
    description = app.screen(:support_description) do |prompt|
      prompt.ask "Please describe your issue:",
        validate: ->(desc) {
          return "Description must be at least 20 characters" if desc.length < 20
          nil
        }
    end

    # Contact preference
    contact_method = app.screen(:support_contact_method) do |prompt|
      prompt.select "How would you like us to contact you?", {
        "whatsapp" => "📱 WhatsApp",
        "phone" => "📞 Phone Call",
        "email" => "📧 Email"
      }
    end

    # Generate support ticket
    ticket_id = "SUP#{Time.current.to_i}"
    
    # Confirmation with support document
    app.say "Support ticket created: ##{ticket_id}\n\nWe'll contact you within 24 hours via #{contact_method}.",
      media: {
        type: :document,
        url: "https://flowchat-demo.com/support/#{ticket_id}.pdf",
        filename: "support_ticket_#{ticket_id}.pdf"
      }

    main_menu
  end

  def clear_cart
    confirm = app.screen(:confirm_clear_cart) do |prompt|
      prompt.yes? "Are you sure you want to clear your cart?"
    end

    if confirm
      app.session.set(:cart, [])
      app.say "Cart cleared! 🗑️"
    end

    main_menu
  end

  def remove_item_from_cart
    cart = app.session.get(:cart) || []
    
    if cart.empty?
      app.say "Cart is already empty!"
      main_menu
      return
    end

    # Show items to remove
    item_options = cart.map.with_index do |item, index|
      [index, "#{index + 1}. #{item[:name]} x#{item[:quantity]}"]
    end.to_h

    selected_index = app.screen(:remove_item_selection) do |prompt|
      prompt.select "Which item would you like to remove?", item_options
    end

    removed_item = cart.delete_at(selected_index)
    app.session.set(:cart, cart)

    app.say "Removed: #{removed_item[:name]} ❌"
    view_cart
  end

  # Helper methods
  def generate_order_id
    "ORD#{Time.current.to_i}#{rand(100..999)}"
  end

  def luhn_valid?(card_number)
    # Simplified Luhn algorithm for demo
    digits = card_number.chars.map(&:to_i).reverse
    sum = digits.each_with_index.sum do |digit, index|
      if index.odd?
        doubled = digit * 2
        doubled > 9 ? doubled - 9 : doubled
      else
        digit
      end
    end
    sum % 10 == 0
  end

  def reorder_items(items)
    # Add items back to cart
    cart = app.session.get(:cart) || []
    items.each { |item| cart << item }
    app.session.set(:cart, cart)
    
    app.say "Items added to your cart! 🛒"
    view_cart
  end

  def show_account_info
    customer_data = app.session.get(:customer_data)
    orders = app.session.get(:orders) || []
    
    info = "Account Information:\n\n"
    info += "Name: #{customer_data[:name]}\n"
    info += "Phone: #{customer_data[:phone]}\n"
    info += "Age: #{customer_data[:age]}\n"
    info += "Dietary Preference: #{customer_data[:dietary_preference].titleize}\n"
    info += "Total Orders: #{orders.length}\n"
    info += "Member Since: #{customer_data[:registered_at]}"
    
    app.say info
    account_settings
  end

  def update_dietary_preferences
    new_preference = app.screen(:update_dietary_preference) do |prompt|
      prompt.select "Update dietary preferences:", {
        "none" => "No restrictions",
        "vegetarian" => "Vegetarian",
        "vegan" => "Vegan", 
        "gluten_free" => "Gluten-free",
        "keto" => "Keto",
        "halal" => "Halal"
      }
    end

    customer_data = app.session.get(:customer_data)
    customer_data[:dietary_preference] = new_preference
    app.session.set(:customer_data, customer_data)

    app.say "Dietary preferences updated! ✅"
    account_settings
  end

  def update_customer_phone
    new_phone = app.screen(:update_phone) do |prompt|
      prompt.ask "Enter your new phone number:",
        transform: ->(input) { input.strip.gsub(/[\s\-\(\)]/, '') },
        validate: ->(input) {
          return "Phone number must start with +" unless input.start_with?('+')
          return "Phone number must be 8-15 digits after +" unless input[1..-1].match?(/\A\d{8,15}\z/)
          nil
        }
    end

    customer_data = app.session.get(:customer_data)
    customer_data[:phone] = new_phone
    app.session.set(:customer_data, customer_data)

    app.say "Phone number updated successfully! ✅"
    account_settings
  end

  def delete_account
    confirm = app.screen(:confirm_delete_account) do |prompt|
      prompt.yes? "⚠️ Are you sure you want to delete your account? This cannot be undone."
    end

    if confirm
      double_confirm = app.screen(:double_confirm_delete) do |prompt|
        prompt.yes? "This will permanently delete all your data. Are you absolutely sure?"
      end

      if double_confirm
        # Clear all session data
        app.session.clear
        app.say "Your account has been deleted. Thank you for using FlowChat Restaurant! 👋"
      else
        app.say "Account deletion cancelled."
        account_settings
      end
    else
      account_settings
    end
  end
end 
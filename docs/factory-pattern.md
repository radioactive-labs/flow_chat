# Factory Pattern

The Factory pattern provides centralized processor configuration, eliminating duplication between webhook controllers and background jobs.

## Quick Start

### 1. Register Factories

Register your processor configurations once in an initializer:

```ruby
# config/initializers/flow_chat.rb

FlowChat::Factory.register :whatsapp do |controller|
  processor = FlowChat::Processor.new(controller) do |config|
    config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
    config.use_session_store FlowChat::Session::CacheSessionStore
    config.use_session_config(boundaries: [:flow])
  end
  processor.run(WhatsAppFlow, :start)
end

FlowChat::Factory.register :intercom do |controller|
  processor = FlowChat::Processor.new(controller) do |config|
    config.use_gateway FlowChat::Intercom::Gateway::IntercomApi
    config.use_session_store FlowChat::Session::CacheSessionStore
    config.use_session_config(boundaries: [:conversation], identifier: :conversation_id)
  end
  processor.run(IntercomFlow, :start)
end
```

### 2. Use in Controllers

Execute factories directly in webhook controllers:

```ruby
# app/controllers/webhooks_controller.rb
class WebhooksController < ApplicationController
  def whatsapp
    FlowChat::Factory.execute(:whatsapp, controller: self)
  end

  def intercom
    FlowChat::Factory.execute(:intercom, controller: self)
  end
end
```

### 3. Use with Async (Recommended)

Register factory with async support for background processing:

```ruby
# config/initializers/flow_chat.rb
FlowChat::Factory.register :whatsapp do |controller|
  processor = FlowChat::Processor.new(controller) do |config|
    config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
    config.use_session_store FlowChat::Session::CacheSessionStore
    config.use_session_config(boundaries: [:flow])
    config.use_async(factory: :whatsapp)  # Self-referencing for async
  end
  processor.run(WhatsAppFlow, :start)
end

# app/controllers/webhooks_controller.rb
class WebhooksController < ApplicationController
  def whatsapp
    FlowChat::Factory.execute(:whatsapp, controller: self)
  end
end
```

**How it works:**
1. Webhook receives request
2. `use_async(factory: :whatsapp)` automatically uses `GenericAsyncJob`
3. Job is enqueued with `factory: :whatsapp` parameter
4. Background worker executes `FlowChat::Factory.execute(:whatsapp, controller: background_controller)`
5. Flow processes in background with same configuration

## Benefits

### 1. Single Source of Truth

Define processor configuration once, use everywhere:

```ruby
# Before: Duplicated configuration
# Webhook controller
processor = FlowChat::Processor.new(self) do |config|
  config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
  config.use_session_store FlowChat::Session::CacheSessionStore
  config.use_session_config(boundaries: [:flow])
end

# Background job (duplicate!)
processor = FlowChat::Processor.new(controller) do |config|
  config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
  config.use_session_store FlowChat::Session::CacheSessionStore
  config.use_session_config(boundaries: [:flow])
end

# After: Single registration
FlowChat::Factory.register :whatsapp do |controller|
  processor = FlowChat::Processor.new(controller) do |config|
    config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
    config.use_session_store FlowChat::Session::CacheSessionStore
    config.use_session_config(boundaries: [:flow])
  end
  processor.run(WhatsAppFlow, :start)
end

# Use everywhere with one line
FlowChat::Factory.execute(:whatsapp, controller: self)
```

### 2. No Custom Job Classes

For simple cases, use `GenericAsyncJob` automatically:

```ruby
# No need to create MyFlowJob class
config.use_async(factory: :whatsapp)
```

### 3. Context-Aware Execution

Same factory works in both webhook and background contexts:

```ruby
# Webhook context - processes inline or enqueues
FlowChat::Factory.execute(:whatsapp, controller: webhook_controller)

# Background context - always processes inline
FlowChat::Factory.execute(:whatsapp, controller: background_controller)
```

Gateways automatically detect the context and prevent double-enqueueing.

### 4. Easy Testing

Test factories in isolation:

```ruby
RSpec.describe "WhatsApp Factory" do
  it "executes successfully" do
    controller = mock_controller
    expect {
      FlowChat::Factory.execute(:whatsapp, controller: controller)
    }.not_to raise_error
  end
end
```

## API Reference

### Registration

**`FlowChat::Factory.register(name, &block)`**

Register a factory with a given name.

```ruby
FlowChat::Factory.register :my_flow do |controller|
  # Build and run processor
  processor = FlowChat::Processor.new(controller) do |config|
    # ... configuration
  end
  processor.run(MyFlow, :start)
end
```

**Parameters:**
- `name` (Symbol): Unique factory identifier
- `block` (Proc): Factory block receiving `controller`

**Returns:** `nil`

### Execution

**`FlowChat::Factory.execute(name, controller:)`**

Execute a registered factory.

```ruby
FlowChat::Factory.execute(:my_flow, controller: self)
```

**Parameters:**
- `name` (Symbol): Factory name to execute
- `controller` (Object): Rails controller or BackgroundController

**Returns:** Result of factory block

**Raises:**
- `FlowChat::Factory::FactoryNotFoundError` if factory not registered

### Introspection

**`FlowChat::Factory.registered?(name)`**

Check if factory is registered.

```ruby
FlowChat::Factory.registered?(:whatsapp)  # => true
```

**`FlowChat::Factory.registered_factories`**

Get all registered factory names.

```ruby
FlowChat::Factory.registered_factories  # => [:whatsapp, :intercom, :ussd]
```

**`FlowChat::Factory.clear!`**

Clear all registered factories (primarily for testing).

```ruby
FlowChat::Factory.clear!
```

## Advanced Patterns

### Environment-Specific Factories

Create different configurations per environment:

```ruby
if Rails.env.production?
  FlowChat::Factory.register :whatsapp do |controller|
    processor = FlowChat::Processor.new(controller) do |config|
      config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
      config.use_session_store FlowChat::Session::CacheSessionStore
    end
    processor.run(ProductionFlow, :start)
  end
else
  FlowChat::Factory.register :whatsapp do |controller|
    processor = FlowChat::Processor.new(controller) do |config|
      config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
      config.use_session_store FlowChat::Session::RailsSessionStore
    end
    processor.run(DevelopmentFlow, :start)
  end
end
```

### Multiple Variants

Register multiple factories for the same platform:

```ruby
FlowChat::Factory.register :whatsapp_support do |controller|
  processor = FlowChat::Processor.new(controller) do |config|
    config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
    config.use_session_store FlowChat::Session::CacheSessionStore
  end
  processor.run(SupportFlow, :start)
end

FlowChat::Factory.register :whatsapp_sales do |controller|
  processor = FlowChat::Processor.new(controller) do |config|
    config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
    config.use_session_store FlowChat::Session::CacheSessionStore
  end
  processor.run(SalesFlow, :start)
end

# Use based on routing
def whatsapp
  factory = params[:department] == 'sales' ? :whatsapp_sales : :whatsapp_support
  FlowChat::Factory.execute(factory, controller: self)
end
```

### Accessing Request Data

Factories receive the controller, which includes request data:

```ruby
FlowChat::Factory.register :whatsapp do |controller|
  # Access request params
  user_id = controller.params[:user_id]
  platform = controller.request.headers["User-Agent"]

  processor = FlowChat::Processor.new(controller) do |config|
    config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
    config.use_session_store FlowChat::Session::CacheSessionStore
  end

  # Route to different flows based on params
  flow = user_id.start_with?('premium_') ? PremiumFlow : StandardFlow
  processor.run(flow, :start)
end
```

## Migration Guide

### From Duplicate Configuration

**Before:**
```ruby
# Webhook controller
class WebhooksController < ApplicationController
  def whatsapp
    processor = FlowChat::Processor.new(self) do |config|
      config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
      config.use_session_store FlowChat::Session::CacheSessionStore
      config.use_async(WhatsAppFlowJob)
    end
    processor.run(WhatsAppFlow, :start)
  end
end

# Background job (duplicate!)
class WhatsAppFlowJob < FlowChat::AsyncJob
  def execute(controller, **job_params)
    processor = FlowChat::Processor.new(controller) do |config|
      config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
      config.use_session_store FlowChat::Session::CacheSessionStore
    end
    processor.run(WhatsAppFlow, :start)
  end
end
```

**After:**
```ruby
# config/initializers/flow_chat.rb
FlowChat::Factory.register :whatsapp do |controller|
  processor = FlowChat::Processor.new(controller) do |config|
    config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
    config.use_session_store FlowChat::Session::CacheSessionStore
    config.use_async(factory: :whatsapp)  # Self-referencing for async
  end
  processor.run(WhatsAppFlow, :start)
end

# Webhook controller - ONE LINE!
class WebhooksController < ApplicationController
  def whatsapp
    FlowChat::Factory.execute(:whatsapp, controller: self)
  end
end

# No custom job class needed!
```

## See Also

- [Async Background Processing](async-background-processing.md) - Using factories with async jobs
- [Session Management](session-management.md) - Configuring session stores in factories
- [Gateways](gateways.md) - Platform-specific gateway configuration

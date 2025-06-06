# WhatsApp Setup Guide

This guide covers comprehensive WhatsApp configuration for FlowChat, including security, multi-tenant setups, and different processing modes.

## Credential Configuration

FlowChat supports multiple ways to configure WhatsApp credentials:

### Option 1: Rails Credentials

```bash
rails credentials:edit
```

```yaml
whatsapp:
  access_token: "your_access_token"
  phone_number_id: "your_phone_number_id"
  verify_token: "your_verify_token"
  app_id: "your_app_id"
  app_secret: "your_app_secret"
  business_account_id: "your_business_account_id"
  skip_signature_validation: false  # Set to true only for development/testing
```

### Option 2: Environment Variables

```bash
export WHATSAPP_ACCESS_TOKEN="your_access_token"
export WHATSAPP_PHONE_NUMBER_ID="your_phone_number_id" 
export WHATSAPP_VERIFY_TOKEN="your_verify_token"
export WHATSAPP_APP_ID="your_app_id"
export WHATSAPP_APP_SECRET="your_app_secret"
export WHATSAPP_BUSINESS_ACCOUNT_ID="your_business_account_id"
export WHATSAPP_SKIP_SIGNATURE_VALIDATION="false"
```

### Option 3: Per-Setup Configuration

For multi-tenant applications:

```ruby
custom_config = FlowChat::Whatsapp::Configuration.new
custom_config.access_token = "your_specific_access_token"
custom_config.phone_number_id = "your_specific_phone_number_id"
custom_config.verify_token = "your_specific_verify_token"
custom_config.app_id = "your_specific_app_id"
custom_config.app_secret = "your_specific_app_secret"
custom_config.business_account_id = "your_specific_business_account_id"
custom_config.skip_signature_validation = false

processor = FlowChat::Whatsapp::Processor.new(self) do |config|
  config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi, custom_config
  config.use_session_store FlowChat::Session::CacheSessionStore
end
```

## Message Handling Modes

Configure message processing behavior in `config/initializers/flowchat.rb`:

### Inline Mode (Default)

Process messages synchronously:

```ruby
FlowChat::Config.whatsapp.message_handling_mode = :inline
```

### Background Mode

Process flows synchronously, send responses asynchronously:

```ruby
FlowChat::Config.whatsapp.message_handling_mode = :background
FlowChat::Config.whatsapp.background_job_class = 'WhatsappMessageJob'
```

### Simulator Mode

Return response data instead of sending via WhatsApp API:

```ruby
FlowChat::Config.whatsapp.message_handling_mode = :simulator
```

## Security Configuration

### Webhook Signature Validation (Production)

```ruby
custom_config.app_secret = "your_whatsapp_app_secret"
custom_config.skip_signature_validation = false  # Default: enforce validation
```

### Development Mode

```ruby
custom_config.app_secret = nil
custom_config.skip_signature_validation = true  # Disable validation
```

⚠️ **Security Warning**: Only disable signature validation in development/testing environments.

## Multi-Tenant Setup

See [examples/multi_tenant_whatsapp_controller.rb](../examples/multi_tenant_whatsapp_controller.rb) for a complete multi-tenant implementation.

## Background Job Setup

When using background jobs with programmatic WhatsApp configurations, you must register configurations in an initializer so they're available to background jobs:

```ruby
# config/initializers/whatsapp_configs.rb
tenant_a_config = FlowChat::Whatsapp::Configuration.new(:tenant_a)
tenant_a_config.access_token = "tenant_a_token"
tenant_a_config.phone_number_id = "tenant_a_phone"
tenant_a_config.verify_token = "tenant_a_verify"
tenant_a_config.app_secret = "tenant_a_secret"
# Configuration is automatically registered as :tenant_a

tenant_b_config = FlowChat::Whatsapp::Configuration.new(:tenant_b)
tenant_b_config.access_token = "tenant_b_token"
tenant_b_config.phone_number_id = "tenant_b_phone"
tenant_b_config.verify_token = "tenant_b_verify"
tenant_b_config.app_secret = "tenant_b_secret"
# Configuration is automatically registered as :tenant_b
```

Then reference the named configuration in your controller:

```ruby
processor = FlowChat::Whatsapp::Processor.new(self) do |config|
  # Use registered configuration by name
  tenant_config = FlowChat::Whatsapp::Configuration.get(:tenant_a)
  config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi, tenant_config
  config.use_session_store FlowChat::Session::CacheSessionStore
end
```

**Why this is required:** Background jobs run in a separate context and cannot access configurations created in controller actions. Registered configurations are globally available.

**Alternative:** Override the job's configuration resolution logic (see examples).

See [examples/whatsapp_message_job.rb](../examples/whatsapp_message_job.rb) for job implementation and [Background Jobs Guide](background-jobs.md) for detailed setup.

## Troubleshooting

### Common Issues

**Configuration Error**: Check that all required credentials are set
**Signature Validation Failed**: Verify app_secret matches your WhatsApp app
**Timeout Issues**: Consider using background mode for high-volume applications

### Debug Mode

Enable debug logging in development:

```ruby
# config/environments/development.rb
config.log_level = :debug
``` 
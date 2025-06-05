# FlowChat Security Guide

This guide covers the security features and best practices for FlowChat, including webhook signature validation and simulator authentication.

## Overview

FlowChat includes comprehensive security features to protect your WhatsApp and USSD applications:

- **Webhook Signature Validation**: Verify that WhatsApp webhooks are authentic
- **Simulator Authentication**: Secure access to the testing simulator
- **Configuration Validation**: Prevent insecure configurations
- **Environment-Specific Security**: Different security levels per environment

## WhatsApp Webhook Security

### Signature Validation

FlowChat automatically validates WhatsApp webhook signatures using HMAC-SHA256 to ensure requests come from WhatsApp.

#### Required Configuration

For webhook signature validation, you need to configure your WhatsApp app secret:

```ruby
# Using Rails credentials
rails credentials:edit
```

```yaml
whatsapp:
  app_secret: "your_whatsapp_app_secret"
  # ... other credentials
```

Or using environment variables:

```bash
export WHATSAPP_APP_SECRET="your_whatsapp_app_secret"
```

#### Security Modes

FlowChat supports two security modes for webhook validation:

**1. Full Security (Recommended for Production)**

```ruby
config = FlowChat::Whatsapp::Configuration.new
config.app_secret = "your_whatsapp_app_secret"  # Required
config.skip_signature_validation = false        # Default: enforce validation
```

**2. Development Mode (Testing Only)**

```ruby
config = FlowChat::Whatsapp::Configuration.new
config.app_secret = nil                         # Not required when disabled
config.skip_signature_validation = true         # Explicitly disable validation
```

⚠️ **Security Warning**: Never disable signature validation in production environments.

#### Configuration Error Handling

When `app_secret` is missing and validation is not explicitly disabled, FlowChat raises a `ConfigurationError`:

```ruby
begin
  processor.run WelcomeFlow, :main_page
rescue FlowChat::Whatsapp::ConfigurationError => e
  Rails.logger.error "Security configuration error: #{e.message}"
  head :internal_server_error
end
```

The error message provides clear guidance:

```
WhatsApp app_secret is required for webhook signature validation. 
Either configure app_secret or set skip_signature_validation=true to explicitly disable validation.
```

### Environment-Specific Security

Configure different security levels per environment:

```ruby
# config/initializers/flowchat.rb
case Rails.env
when 'development'
  # Relaxed security for easier development
  config.skip_signature_validation = true
  
when 'test'
  # Skip validation for deterministic testing
  config.skip_signature_validation = true
  
when 'staging', 'production'
  # Full security for production-like environments
  config.skip_signature_validation = false
  
  # Ensure app_secret is configured
  if ENV['WHATSAPP_APP_SECRET'].blank?
    raise "WHATSAPP_APP_SECRET required for #{Rails.env} environment"
  end
end
```

## Simulator Security

### Authentication System

The FlowChat simulator uses secure HMAC-SHA256 signed cookies for authentication. This prevents unauthorized access to your simulator endpoints.

#### Required Configuration

Configure a simulator secret in your initializer:

```ruby
# config/initializers/flowchat.rb
FlowChat::Config.simulator_secret = "your_secure_secret_here"
```

#### Environment-Specific Secrets

Use different secrets per environment:

```ruby
case Rails.env
when 'development', 'test'
  # Use Rails secret key with environment suffix
  FlowChat::Config.simulator_secret = Rails.application.secret_key_base + "_#{Rails.env}"
  
when 'staging', 'production'
  # Use environment variable for production
  FlowChat::Config.simulator_secret = ENV['FLOWCHAT_SIMULATOR_SECRET']
  
  if FlowChat::Config.simulator_secret.blank?
    Rails.logger.warn "FLOWCHAT_SIMULATOR_SECRET not configured. Simulator will be unavailable."
  end
end
```

#### Cookie Security

Simulator cookies are automatically configured with security best practices:

- **HMAC-SHA256 signed**: Prevents tampering
- **24-hour expiration**: Limits exposure window
- **Secure flag**: Only sent over HTTPS in production
- **HttpOnly flag**: Prevents XSS access
- **SameSite=Lax**: CSRF protection

#### Enabling Simulator Mode

Enable simulator mode only when needed:

```ruby
# Enable simulator only in development/staging
enable_simulator = Rails.env.development? || Rails.env.staging?

processor = FlowChat::Whatsapp::Processor.new(self, enable_simulator: enable_simulator) do |config|
  config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
  config.use_session_store FlowChat::Session::CacheSessionStore
end
```

### Simulator Request Flow

1. **User visits simulator**: Browser requests `/simulator`
2. **Cookie generation**: Server generates HMAC-signed cookie
3. **Simulator requests**: Include valid cookie for authentication
4. **Cookie validation**: Server validates HMAC signature and timestamp
5. **Request processing**: Continues if authentication succeeds

## Security Best Practices

### Production Checklist

✅ **WhatsApp Security**
- Configure `app_secret` for webhook validation
- Set `skip_signature_validation = false`
- Use environment variables for secrets
- Handle `ConfigurationError` exceptions

✅ **Simulator Security**  
- Configure `simulator_secret` using environment variables
- Enable simulator only in development/staging
- Use unique secrets per environment

✅ **Environment Configuration**
- Different security levels per environment
- Fail fast on missing required configuration
- Log security warnings appropriately

✅ **Error Handling**
- Catch and log `ConfigurationError` exceptions
- Return appropriate HTTP status codes
- Don't expose sensitive information in errors

### Development Guidelines

**DO:**
- Use Rails `secret_key_base` + suffix for development secrets
- Skip webhook validation in development for easier testing
- Enable simulator mode for testing
- Use test-specific credentials in test environment

**DON'T:**
- Hardcode secrets in source code
- Disable security in production
- Use production secrets in development
- Commit secrets to version control

### Example Secure Configuration

```ruby
# config/initializers/flowchat.rb
case Rails.env
when 'development'
  FlowChat::Config.simulator_secret = Rails.application.secret_key_base + "_dev"
  FlowChat::Config.whatsapp.message_handling_mode = :simulator
  
when 'test'
  FlowChat::Config.simulator_secret = "test_secret_#{Rails.application.secret_key_base}"
  FlowChat::Config.whatsapp.message_handling_mode = :simulator
  
when 'staging'
  FlowChat::Config.simulator_secret = ENV.fetch('FLOWCHAT_SIMULATOR_SECRET')
  FlowChat::Config.whatsapp.message_handling_mode = :inline
  
when 'production'
  FlowChat::Config.simulator_secret = ENV.fetch('FLOWCHAT_SIMULATOR_SECRET')
  FlowChat::Config.whatsapp.message_handling_mode = :background
  FlowChat::Config.whatsapp.background_job_class = 'WhatsappMessageJob'
end
```

## Testing Security Features

### Webhook Signature Validation Tests

```ruby
test "webhook accepts valid signature" do
  payload = valid_webhook_payload.to_json
  signature = OpenSSL::HMAC.hexdigest(
    OpenSSL::Digest.new("sha256"),
    "your_app_secret",
    payload
  )

  post "/whatsapp/webhook",
    params: payload,
    headers: { 
      "Content-Type" => "application/json",
      "X-Hub-Signature-256" => "sha256=#{signature}" 
    }

  assert_response :success
end

test "webhook rejects invalid signature" do
  post "/whatsapp/webhook", 
    params: valid_webhook_payload,
    headers: { "X-Hub-Signature-256" => "sha256=invalid_signature" }

  assert_response :unauthorized
end

test "webhook rejects missing signature" do
  post "/whatsapp/webhook", params: valid_webhook_payload
  assert_response :unauthorized
end
```

### Simulator Authentication Tests

```ruby
test "simulator requires valid authentication" do
  post "/whatsapp/webhook", params: {
    simulator_mode: true,
    # ... webhook payload
  }

  assert_response :unauthorized  # No valid simulator cookie
end

test "simulator accepts valid authentication" do
  # Generate valid simulator cookie
  timestamp = Time.now.to_i
  message = "simulator:#{timestamp}"
  signature = OpenSSL::HMAC.hexdigest(
    OpenSSL::Digest.new("sha256"), 
    FlowChat::Config.simulator_secret, 
    message
  )
  
  post "/whatsapp/webhook", 
    params: { simulator_mode: true, /* ... */ },
    cookies: { flowchat_simulator: "#{timestamp}:#{signature}" }

  assert_response :success
end
```

## Troubleshooting

### Common Issues

**1. ConfigurationError: app_secret required**

```
WhatsApp app_secret is required for webhook signature validation.
```

**Solution**: Configure `WHATSAPP_APP_SECRET` environment variable or disable validation explicitly.

**2. Invalid webhook signature**

```
Invalid webhook signature received
```

**Solution**: Verify your `app_secret` matches your WhatsApp app configuration.

**3. Simulator authentication failed**

```
Invalid simulator cookie format
```

**Solution**: Ensure `FlowChat::Config.simulator_secret` is properly configured.

**4. Missing simulator secret**

```
Simulator secret not configured
```

**Solution**: Set `FLOWCHAT_SIMULATOR_SECRET` environment variable or configure in initializer.

### Debug Mode

Enable debug logging for security events:

```ruby
# config/initializers/flowchat.rb
if Rails.env.development?
  FlowChat::Config.logger.level = Logger::DEBUG
end
```

This will log security validation attempts and help troubleshoot configuration issues.

## Security Updates

This security system was introduced in FlowChat v2.0.0 and includes:

- HMAC-SHA256 webhook signature validation
- Secure simulator authentication with signed cookies  
- Environment-specific security configuration
- Comprehensive error handling and logging
- Timing-attack resistant signature comparison

For the latest security updates and recommendations, check the FlowChat changelog and security advisories. 
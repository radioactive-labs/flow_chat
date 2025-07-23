# Testing & Simulation

FlowChat provides a sophisticated web-based simulator for testing conversational flows across multiple platforms (USSD, WhatsApp, HTTP) without requiring actual gateway integrations.

## Built-in Web Simulator

### Overview

The FlowChat simulator is a browser-based testing interface that provides:

- **Multi-Platform Testing**: USSD, WhatsApp, and HTTP with platform-specific UI
- **Real-Time Request Logging**: Complete HTTP traffic monitoring and debugging
- **Security**: HMAC-signed cookie authentication
- **Platform-Specific Rendering**: Accurate simulation of each platform's behavior
- **Configuration Management**: Test multiple endpoints from a single interface

### Setup & Configuration

#### 1. Basic Configuration

```ruby
# config/initializers/flow_chat.rb
FlowChat::Config.simulator_secret = "your_secure_secret_key_here"
```

#### 2. Create Simulator Controller

```ruby
# app/controllers/simulator_controller.rb
class SimulatorController < ApplicationController
  include FlowChat::Simulator::Controller

  def index
    flowchat_simulator
  end

  protected

  # Configure available test endpoints
  def configurations
    {
      ussd_main: {
        name: "USSD (Nalo)",
        description: "USSD integration using Nalo gateway",
        processor_type: "ussd",
        gateway: "nalo",
        endpoint: "/ussd",
        icon: "📱",
        color: "#28a745",
        settings: {
          phone_number: default_phone_number,
          session_timeout: 300
        }
      },
      whatsapp_main: {
        name: "WhatsApp (Cloud API)",
        description: "WhatsApp integration using Cloud API",
        processor_type: "whatsapp",
        gateway: "cloud_api", 
        endpoint: "/whatsapp/webhook",
        icon: "💬",
        color: "#25D366",
        settings: {
          phone_number: default_phone_number,
          contact_name: default_contact_name
        }
      },
      http_api: {
        name: "HTTP API",
        description: "JSON HTTP API endpoint",
        processor_type: "http",
        gateway: "http_simple",
        endpoint: "/http/webhook", 
        icon: "🌐",
        color: "#0066cc",
        settings: {
          user_id: default_phone_number
        }
      }
    }
  end

  def default_phone_number
    "+233244123456"
  end

  def default_contact_name
    "John Doe"
  end

  def default_config_key
    :ussd_main
  end
end
```

#### 3. Add Route

```ruby
# config/routes.rb
Rails.application.routes.draw do
  get '/simulator' => 'simulator#index'
  # ... other routes
end
```

### Security Features

#### HMAC-Signed Cookies

The simulator uses secure, timestamped cookies for authentication:

```ruby
# Automatic cookie generation in simulator controller
def set_simulator_cookie
  simulator_secret = FlowChat::Config.simulator_secret
  timestamp = Time.now.to_i
  message = "simulator:#{timestamp}"
  signature = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), simulator_secret, message)
  
  cookies[:flowchat_simulator] = {
    value: "#{timestamp}:#{signature}",
    expires: 24.hours.from_now,
    secure: request.ssl?,  # HTTPS only in production
    httponly: true,        # Prevent XSS
    same_site: :lax       # CSRF protection
  }
end
```

#### Automatic Enablement

Simulator mode is automatically enabled when:

```ruby
# In processor initialization
enable_simulator: Rails.env.local?  # true for development/test
```

### Platform-Specific Features

#### USSD Testing

**Interface**: Menu-style display with character limits and pagination

**Features**:
- Network-specific character limits (MTN: 160, Airtel: 140, etc.)
- Session timeout simulation
- Menu option selection
- Automatic pagination for long content

**Request Format**:
```ruby
{
  msisdn: "+233244123456",
  text: "user_input", 
  session_id: "session_123",
  network: "mtn"
}
```

#### WhatsApp Testing

**Interface**: Chat-style interface with contact avatars and message history

**Features**:
- Contact name and avatar display
- Interactive buttons and lists
- Media support (images, documents, audio, video)
- Cloud API webhook simulation

**Request Format**:
```javascript
{
  simulator_mode: true,
  entry: [{
    changes: [{
      value: {
        messaging_product: "whatsapp",
        metadata: {
          display_phone_number: "233244123456",
          phone_number_id: "phone_number_id_123"
        },
        messages: [{
          text: { body: "user_input" },
          type: 'text'
        }],
        contacts: [{
          profile: { name: "John Doe" },
          wa_id: "233244123456"
        }]
      }
    }]
  }]
}
```

**Response Handling**:
```javascript
// Simulator expects JSON response for full simulation
{
  mode: "simulator",
  webhook_processed: true,
  would_send: {
    to: "233244123456",
    type: "text",
    text: { body: "Response message" }
  },
  message_info: {
    to: "233244123456",
    contact_name: "John Doe",
    timestamp: "2024-01-01T12:00:00Z"
  }
}
```

#### HTTP Testing

**Interface**: API-style interface showing JSON request/response

**Features**:
- JSON payload display
- Session management
- Custom headers
- Error handling

**Request Format**:
```javascript
{
  session_id: "session_123",
  user_id: "+233244123456",
  input: "user_input",
  simulator_mode: true
}
```

### Request Logging & Debugging

#### Real-Time Traffic Monitoring

The simulator provides comprehensive request logging:

```javascript
// Automatic logging of all HTTP traffic
addRequestLog('POST', endpoint, requestData, responseData, statusCode, errorMessage)
```

**Log Information**:
- Request method and URL
- Complete request payload
- Response status and data
- Timestamps and duration
- Error messages with helpful debugging hints

#### Error Handling

The simulator provides detailed error messages for common issues:

- **Connection Failures**: CORS, SSL, network issues
- **404 Not Found**: Route configuration problems  
- **500 Server Errors**: Application errors
- **Authentication Issues**: Invalid simulator cookies

### Enabling Simulator Mode in Your Endpoints

#### For WhatsApp Endpoints

Your WhatsApp processor automatically handles simulator mode:

```ruby
class WhatsappController < ApplicationController
  def webhook
    processor = FlowChat::Whatsapp::Processor.new(self, enable_simulator: !Rails.env.production?) do |config|
      config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
      config.use_session_store FlowChat::Session::CacheSessionStore
    end

    processor.run WelcomeFlow, :main_page
  end
end
```

#### For HTTP Endpoints

HTTP endpoints work automatically with the simulator:

```ruby
class HttpController < ApplicationController  
  def webhook
    processor = FlowChat::Http::Processor.new(self) do |config|
      config.use_gateway FlowChat::Http::Gateway::Simple
      config.use_session_store FlowChat::Session::CacheSessionStore
    end

    processor.run WelcomeFlow, :main_page
  end
end
```

### Usage Workflow

#### 1. Start the Simulator

```bash
rails server
# Visit http://localhost:3000/simulator
```

#### 2. Configure Test Environment

- Select endpoint from configuration dropdown
- Set phone number and contact name
- Choose platform type (USSD/WhatsApp/HTTP)

#### 3. Test Conversation Flows

- Click "Start Session" to begin
- Send messages through the platform-specific interface
- Monitor request/response logs in real-time
- Reset session to test different scenarios

#### 4. Debug Issues

- Check request logs for HTTP traffic details
- Verify endpoint responses and status codes
- Review error messages for configuration issues
- Test different platforms and configurations

### Best Practices

#### Security

- Always set `FlowChat::Config.simulator_secret` in production
- Use secure cookies over HTTPS in production
- Restrict simulator access to development/staging environments

#### Testing Strategy

1. **Start with Simulator**: Test flows before gateway integration
2. **Test All Platforms**: Verify behavior across USSD, WhatsApp, HTTP
3. **Check Character Limits**: Test USSD character restrictions
4. **Verify Session Management**: Test session boundaries and persistence
5. **Monitor Request Logs**: Debug integration issues in real-time

#### Performance

- Use simulator for rapid prototyping and debugging
- Test edge cases and error conditions safely
- Validate webhook payloads before production deployment

The FlowChat simulator provides a complete testing environment that accurately simulates real-world platform behavior while offering comprehensive debugging capabilities for efficient development and testing workflows.



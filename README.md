# FlowChat

[![CI](https://github.com/radioactive-labs/flow_chat/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/radioactive-labs/flow_chat/actions/workflows/ci.yml)
[![Gem Version](https://badge.fury.io/rb/flow_chat.svg)](https://badge.fury.io/rb/flow_chat)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%202.3.0-red.svg)](https://www.ruby-lang.org/)
[![Rails](https://img.shields.io/badge/rails-%3E%3D%206.0-red.svg)](https://rubyonrails.org/)

FlowChat is a powerful Rails framework for building sophisticated conversational interfaces across **multiple platforms** with a **pluggable gateway architecture**. Create interactive flows with menus, prompts, validation, media support, and session management using a unified, intuitive API that works across USSD, WhatsApp, HTTP, and any custom platforms you build.

## ✨ Key Features

- **🔄 Unified API**: Single codebase that works across all platforms
- **🔌 Pluggable Gateways**: Extensible architecture supporting multiple backends per platform
- **📱 Multi-Platform**: Out of the box support for USSD, WhatsApp, HTTP (and more coming soon), with simulator for testing
- **🎯 Screen-Based Navigation**: Intuitive screen() method for building conversational flows
- **💾 Advanced Session Management**: Flexible session boundaries and storage options
- **🔧 Middleware Architecture**: Extensible middleware system for custom processing
- **🎨 Rich Prompts**: Support for text, media, selections, yes/no prompts, validation, and transformations
- **📊 Built-in Instrumentation**: Comprehensive logging and metrics collection
- **🧪 Testing Support**: Built-in simulator for development and testing
- **🏢 Multi-Tenancy**: In-built support for custom configuration per tenant and URL-based isolation
- **🚀 Background Processing**: Job queue support for WhatsApp messaging

## 🚀 Quick Start

### Installation

Add FlowChat to your Rails application:

```ruby
# Gemfile
gem 'flow_chat'
```

```bash
bundle install
```

### Define your flow

```ruby
# app/flow_chat/welcome_flow.rb

class WelcomeFlow < FlowChat::Flow
  def main_page
    name = app.screen(:name) do |prompt|
      prompt.ask "Welcome! What's your name?",
        transform: ->(input) { input.strip.titleize }
    end

    choice = app.screen(:main_menu) do |prompt|
      prompt.select "Hi #{name}! Choose:", {
        "1" => "Account Info",
        "2" => "Make Payment",
        "3" => "Support"
      }
    end

    case choice
    when "1"
      show_account_info
    when "2"
      make_payment  
    when "3"
      app.say "Call us: 123-456-7890"
    end
  end

  # ... implement your flow methods
end
```

### Basic USSD Application

```ruby
# app/controllers/ussd_controller.rb
class UssdController < ApplicationController
  skip_forgery_protection

  def process_request
    processor = FlowChat::Processor.new(self) do |config|
      config.use_gateway FlowChat::Ussd::Gateway::Nalo
      config.use_session_store FlowChat::Session::RailsSessionStore
    end

    processor.run WelcomeFlow, :main_page
  end
end
```

### Basic WhatsApp Application

```ruby
# app/controllers/whatsapp_controller.rb
class WhatsappController < ApplicationController
  skip_forgery_protection

  def webhook
    processor = FlowChat::Processor.new(self) do |config|
      config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
      config.use_session_store FlowChat::Session::CacheSessionStore
    end

    processor.run WelcomeFlow, :main_page
  end
end
```

### Basic HTTP API Application

```ruby
# app/controllers/api_controller.rb
class ApiController < ApplicationController
  def chat
    processor = FlowChat::Processor.new(self) do |config|
      config.use_gateway FlowChat::Http::Gateway::Simple
      config.use_session_store FlowChat::Session::RailsSessionStore
    end

    processor.run WelcomeFlow, :main_page
  end
end
```
> Same WelcomeFlow works across ALL platforms!


## 🏗️ Architecture

FlowChat uses a **composition-based architecture** with these core components:

- **Processor**: Orchestrates request processing through middleware stack
- **Gateway**: Platform-specific request/response handling (Nalo, WhatsApp Cloud API)
- **App**: Unified application interface with screen-based navigation
- **Session**: Flexible session management with configurable boundaries
- **Middleware**: Extensible processing pipeline

```
┌─────────────┐    ┌──────────────┐    ┌─────────────┐
│   Gateway   │ -> │ Session      │ -> │ Custom      │
│             │    │ Middleware   │    │ Middleware  │
└─────────────┘    └──────────────┘    └─────────────┘
                                              │
                                              v
┌─────────────┐    ┌──────────────┐    ┌─────────────┐
│ Flow/Action │ <- │   Executor   │ <- │     App     │
│             │    │              │    │             │
└─────────────┘    └──────────────┘    └─────────────┘
```

## 🔌 Pluggable Gateway Architecture

FlowChat's power comes from its pluggable gateway system. Each platform can have multiple gateway implementations:

```ruby
# Create your own SMS gateway
class MyCompany::Sms::Gateway::Twilio
  def initialize(app, config)
    @app = app
    @config = config
  end

  def call(context)
    # Parse Twilio webhook, set context values
    context["request.msisdn"] = params["From"]
    context["request.platform"] = :sms
    context.input = params["Body"]
    
    # Process through middleware
    type, prompt, choices, media = @app.call(context)
    
    # Send response via Twilio API
    send_sms_response(prompt, to: context["request.msisdn"])
  end

  # Optional: Configure platform-specific middleware
  def self.configure_middleware_stack(builder, custom_middleware)
    builder.use MyCompany::Sms::MessageTransformMiddleware
    builder.use custom_middleware
  end
end

# Use your custom gateway
processor = FlowChat::Processor.new(self) do |config|
  config.use_gateway MyCompany::Sms::Gateway::Twilio, sms_config
end
```

## 📚 Documentation

### Getting Started
- [**Getting Started Guide**](docs/getting-started.md) - Comprehensive setup and first app
- [**Architecture Overview**](docs/architecture.md) - Deep dive into FlowChat's design
- [**Configuration**](docs/configuration.md) - Complete configuration reference

### Platform Guides
- [**USSD Development**](docs/platforms/ussd.md) - USSD-specific features and examples
- [**WhatsApp Development**](docs/platforms/whatsapp.md) - WhatsApp Business API integration
- [**HTTP Development**](docs/platforms/http.md) 🚧 - API endpoints and webhooks
- [**Multi-Platform Apps**](docs/platforms/multi-platform.md) 🚧 - Building unified experiences

### Advanced Topics
- [**Gateway Development**](docs/gateway-development.md) - Creating custom gateways and platforms
- [**Session Management**](docs/session-management.md) 🚧 - Session boundaries and storage
- [**Middleware Development**](docs/middleware.md) 🚧 - Creating custom middleware
- [**Testing & Simulation**](docs/testing.md) - Testing strategies and simulator usage
- [**Background Jobs**](docs/background-jobs.md) 🚧 - Async processing for WhatsApp

### API Reference
- [**Core API**](docs/api-reference/core.md) 🚧 - Processor, App, Flow classes
- [**Prompts & Validation**](docs/api-reference/prompts.md) 🚧 - Interactive prompts and validation
- [**Gateways**](docs/api-reference/gateways.md) 🚧 - Platform gateway interfaces
- [**Session Stores**](docs/api-reference/session-stores.md) 🚧 - Session storage options

## 🎯 Core Concepts

### Screen-Based Navigation

Build conversational flows using the intuitive `screen()` method:

```ruby
def registration_flow
  # Each screen automatically handles state and navigation
  email = app.screen(:email) do |prompt|
    prompt.ask "Enter your email:",
      validate: ->(input) { 
        "Invalid email" unless input.include?("@")
      }
  end

  name = app.screen(:name) do |prompt|
    prompt.ask "Enter your full name:",
      transform: ->(input) { input.strip.titleize }
  end

  # Confirmation screen with rich prompts
  confirmed = app.screen(:confirm) do |prompt|
    prompt.yes? "Confirm registration for #{name} (#{email})?"
  end

  if confirmed
    create_user(name, email)
    app.say "Welcome #{name}! Registration complete."
  else
    app.say "Registration cancelled."
  end
end
```

### Multi-Platform Compatibility

Write once, run everywhere:

```ruby
class MenuFlow < FlowChat::Flow
  def main_menu
    choice = app.screen(:menu) do |prompt|
      prompt.select "Choose an option:", {
        "info" => "📋 Information",      # Rich for WhatsApp
        "help" => "❓ Help",             # Falls back to text for USSD  
        "exit" => "👋 Exit"
      }
    end
    
    # Same logic works on both platforms
    handle_choice(choice)
  end
end
```

### Flexible Session Management

Configure sessions for your use case:

```ruby
# Durable sessions across timeouts
processor = FlowChat::Processor.new(self) do |config|
  config.use_durable_sessions  # Uses user identifier (usually phone number) for session ID
end

# Cross-platform sessions
processor = FlowChat::Processor.new(self) do |config|
  config.use_cross_platform_sessions  # Share sessions between platforms (e.g. USSD & WhatsApp)
end

# URL-based multi-tenancy
processor = FlowChat::Processor.new(self) do |config|
  config.use_url_isolation  # tenant1.app.com vs tenant2.app.com
end
```

## 🛠️ Supported Platforms & Gateways

| Platform | Available Gateways | Features |
|----------|-------------------|----------|
| **USSD** | `Nalo` ✅, Custom | Pagination, choice mapping, session management |
| **WhatsApp** | `CloudApi` ✅, Custom | Rich media, buttons, lists, templates, background jobs |
| **HTTP** | `Simple` ✅, Custom | Testing, webhooks, API endpoints, JSON responses |
| **Simulator** | Built-in ✅ | Development testing, conversation replay, flow debugging |
| **Custom** | *Your Gateway* | Implement any platform by creating a gateway class |

*✅ = Included with FlowChat*

### Gateway Examples

```ruby
# Built-in gateways (included with FlowChat)
config.use_gateway FlowChat::Ussd::Gateway::Nalo
config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi, whatsapp_config
config.use_gateway FlowChat::Http::Gateway::Simple

# Custom gateway examples (you would build these)
config.use_gateway MyCompany::Sms::Gateway::Twilio, twilio_config
config.use_gateway MyCompany::Telegram::Gateway::BotAPI, telegram_config
```

## 📦 Example Applications

- [**USSD Banking App**](docs/examples/ussd-banking.md) 🚧 - Complete banking flow with validation
- [**WhatsApp Customer Service**](docs/examples/whatsapp-support.md) 🚧 - Media support and templates  
- [**HTTP API Chatbot**](docs/examples/http-api.md) 🚧 - JSON API for web/mobile integration
- [**Multi-Platform E-commerce**](docs/examples/multi-platform-shop.md) 🚧 - Unified shopping across USSD, WhatsApp, and HTTP
- [**Multi-Tenant SaaS**](docs/examples/multi-tenant.md) 🚧 - URL-based tenant isolation
- [**Custom Gateway Example**](docs/examples/custom-gateway.md) 🚧 - Building a Telegram gateway

## 🧪 Testing & Development

FlowChat includes a built-in simulator interface for easy development and testing:

```ruby
# Simulator is automatically enabled in development
processor = FlowChat::Processor.new(self) do |config|
  config.use_gateway FlowChat::Ussd::Gateway::Nalo  # or any gateway
end

# Explicitly control simulator mode if needed
processor = FlowChat::Processor.new(self, enable_simulator: false) do |config|
  # Disable simulator even in development
end
```

The simulator provides a web interface for testing your flows during development. It works the same regardless of which gateway you're using, allowing you to test your conversational logic before deploying to actual platforms.

**Learn more**: [Testing & Simulation Guide](docs/testing.md)

## 🤝 Contributing

We welcome contributions!

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

FlowChat is released under the [MIT License](LICENSE.txt).

## 🆘 Support

- **Documentation**: Comprehensive guides in the [docs/](docs/) directory
- **Issues**: [GitHub Issues](https://github.com/radioactive-labs/flow_chat/issues)
- **Discussions**: [GitHub Discussions](https://github.com/radioactive-labs/flow_chat/discussions)

## 🏢 Commercial Support

FlowChat is developed by [Radioactive Labs](https://github.com/radioactive-labs). Commercial support, custom development, and consulting services are available.

---

**Ready to build amazing conversational experiences?** Check out the [Getting Started Guide](docs/getting-started.md) to create your first FlowChat application.

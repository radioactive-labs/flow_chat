# Gateway Development Guide

This guide shows how to build custom gateways to extend FlowChat to new platforms and services. FlowChat's pluggable architecture makes it easy to add support for SMS, Telegram, Slack, voice calls, or any other conversational platform.

## Gateway Interface

Every gateway must implement the basic interface:

> **Note:** The examples in this guide are illustrative implementations to demonstrate the concepts. They are not part of the FlowChat codebase and would need additional work to be production-ready.

```ruby
class YourCustomGateway
  # Required: Initialize with app and optional configuration
  def initialize(app, *config_args)
    @app = app
    @config = config_args.first
  end

  # Required: Process requests through the middleware stack
  def call(context)
    # 1. Parse platform-specific request
    parse_request(context)
    
    # 2. Process through FlowChat middleware stack
    type, prompt, choices, media = @app.call(context)
    
    # 3. Render platform-specific response
    render_response(type, prompt, choices, media, context)
  end

  # Optional: Configure platform-specific middleware
  def self.configure_middleware_stack(builder, custom_middleware)
    builder.use YourPlatform::SpecialMiddleware
    builder.use custom_middleware
    builder.use YourPlatform::ResponseMiddleware
  end
end
```

## Example: Telegram Gateway (Hypothetical)

Here's how you would build a complete Telegram Bot API gateway:

```ruby
module MyCompany
  module Telegram
    module Gateway
      class BotAPI
        include FlowChat::Instrumentation

        def initialize(app, bot_token)
          @app = app
          @bot_token = bot_token
          @api_base = "https://api.telegram.org/bot#{@bot_token}"
        end

        def call(context)
          # 1. Parse Telegram webhook payload
          payload = parse_telegram_webhook(context)
          
          # 2. Set FlowChat context
          set_flowchat_context(context, payload)
          
          # 3. Process through middleware stack
          type, prompt, choices, media = @app.call(context)
          
          # 4. Send response via Telegram API
          send_telegram_response(type, prompt, choices, media, context)
        end

        # Optional: Configure Telegram-specific middleware
        def self.configure_middleware_stack(builder, custom_middleware)
          builder.use MyCompany::Telegram::Middleware::MessageProcessor
          builder.use custom_middleware
          builder.use MyCompany::Telegram::Middleware::ResponseFormatter
        end

        private

        def parse_telegram_webhook(context)
          body = context.controller.request.body.read
          JSON.parse(body)
        rescue JSON::ParserError => e
          Rails.logger.error "Telegram: Invalid JSON: #{e.message}"
          raise "Invalid webhook payload"
        end

        def set_flowchat_context(context, payload)
          message = payload.dig("message")
          callback_query = payload.dig("callback_query")
          
          if message
            # Regular message
            context["request.user_id"] = message.dig("from", "id").to_s
            context["request.message_id"] = message["message_id"].to_s
            context["request.platform"] = :telegram
            context["request.gateway"] = :telegram_bot_api
            context["request.timestamp"] = Time.at(message["date"]).iso8601
            context.input = message["text"]
            
            # Telegram-specific data
            context["telegram.chat_id"] = message.dig("chat", "id")
            context["telegram.username"] = message.dig("from", "username")
            
          elsif callback_query
            # Button press
            context["request.user_id"] = callback_query.dig("from", "id").to_s
            context["request.platform"] = :telegram
            context.input = callback_query["data"]  # Button callback data
            
            context["telegram.chat_id"] = callback_query.dig("message", "chat", "id")
            context["telegram.callback_query_id"] = callback_query["id"]
          end
        end

        def send_telegram_response(type, prompt, choices, media, context)
          chat_id = context["telegram.chat_id"]
          
          response_data = {
            chat_id: chat_id,
            text: prompt
          }

          # Add inline keyboard for choices
          if choices.present?
            keyboard = build_inline_keyboard(choices)
            response_data[:reply_markup] = { inline_keyboard: keyboard }
          end

          # Send message via Telegram API
          send_telegram_api_request("sendMessage", response_data)
        end

        def build_inline_keyboard(choices)
          # Convert FlowChat choices to Telegram inline keyboard
          buttons = choices.map do |value, text|
            [{ text: text, callback_data: value }]
          end
          buttons
        end

        def send_telegram_api_request(method, data)
          uri = URI("#{@api_base}/#{method}")
          
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          
          request = Net::HTTP::Post.new(uri)
          request['Content-Type'] = 'application/json'
          request.body = data.to_json
          
          response = http.request(request)
          
          unless response.code.to_i.between?(200, 299)
            Rails.logger.error "Telegram API error: #{response.code} #{response.body}"
          end
          
          response
        end
      end
    end
  end
end
```

## Example: SMS Gateway (Hypothetical)

Here's how you would build an SMS gateway using Twilio:

```ruby
module MyCompany
  module Sms
    module Gateway
      class Twilio
        include FlowChat::Instrumentation

        def initialize(app, config)
          @app = app
          @account_sid = config.account_sid
          @auth_token = config.auth_token
          @from_number = config.from_number
        end

        def call(context)
          # Parse Twilio webhook
          params = context.controller.params
          
          # Set FlowChat context
          context["request.user_id"] = params["From"]
          context["request.msisdn"] = params["From"]
          context["request.message_id"] = params["MessageSid"]
          context["request.platform"] = :sms
          context["request.gateway"] = :twilio
          context["request.timestamp"] = Time.current.iso8601
          context.input = params["Body"]

          # Process through middleware
          type, prompt, choices, media = @app.call(context)

          # Send SMS response
          send_sms(prompt, to: params["From"], context: context)
        end

        def self.configure_middleware_stack(builder, custom_middleware)
          # SMS-specific processing
          builder.use MyCompany::Sms::Middleware::CharacterLimitMiddleware
          builder.use custom_middleware
          builder.use MyCompany::Sms::Middleware::ChoiceFormatter
        end

        private

        def send_sms(message, to:, context:)
          # Format choices for SMS
          if context["choices"].present?
            choice_text = format_choices_for_sms(context["choices"])
            message = "#{message}\n\n#{choice_text}"
          end

          # Send via Twilio API
          twilio_client.messages.create(
            from: @from_number,
            to: to,
            body: message
          )

          # Instrument message sent
          instrument(FlowChat::Events::MESSAGE_SENT, {
            to: to,
            message: message,
            platform: :sms,
            gateway: :twilio,
            content_length: message.length,
            timestamp: context["request.timestamp"]
          })
        end

        def format_choices_for_sms(choices)
          choices.map.with_index(1) { |(value, text), i| "#{i}. #{text}" }.join("\n")
        end

        def twilio_client
          @twilio_client ||= ::Twilio::REST::Client.new(@account_sid, @auth_token)
        end
      end
    end
  end
end
```

## Custom Middleware

Gateways can define their own middleware for platform-specific processing:

```ruby
module MyCompany
  module Telegram
    module Middleware
      class MessageProcessor
        def initialize(app)
          @app = app
        end

        def call(context)
          # Pre-process Telegram-specific features
          handle_telegram_commands(context)
          handle_telegram_media(context)
          
          result = @app.call(context)
          
          # Post-process response
          format_telegram_response(context, result)
          
          result
        end

        private

        def handle_telegram_commands(context)
          input = context.input
          return unless input&.start_with?('/')

          # Handle Telegram bot commands
          command = input.split.first
          context["telegram.command"] = command
          
          case command
          when "/start"
            context.input = nil  # Start fresh conversation
          when "/help"
            context.input = "help"
          when "/cancel"
            context.input = "cancel"
          end
        end

        def handle_telegram_media(context)
          # Handle photos, documents, etc.
          # Implementation depends on your needs
        end

        def format_telegram_response(context, result)
          # Format response for Telegram's markdown
          type, prompt, choices, media = result
          
          if prompt.is_a?(String)
            # Escape special Telegram markdown characters
            prompt = prompt.gsub(/[_*\[\]()~`>#+=|{}.!-]/, '\\\\\&')
            result[1] = prompt
          end
          
          result
        end
      end
    end
  end
end
```

## Using Your Custom Gateway

Once built, use your gateway like any other:

```ruby
class TelegramController < ApplicationController
  def webhook
    processor = FlowChat::Processor.new(self) do |config|
      config.use_gateway MyCompany::Telegram::Gateway::BotAPI, telegram_bot_token
      config.use_session_store FlowChat::Session::CacheSessionStore
      config.use_durable_sessions  # Use user_id for persistent sessions
    end

    processor.run WelcomeFlow, :start
  end

  private

  def telegram_bot_token
    ENV["TELEGRAM_BOT_TOKEN"]
  end
end
```

## Gateway Configuration

### Configuration Objects

Create configuration classes for complex gateways:

```ruby
module MyCompany
  module Slack
    class Configuration
      attr_accessor :bot_token, :signing_secret, :app_token
      attr_accessor :default_channel, :enable_threads

      def initialize
        @enable_threads = true
        @default_channel = "#general"
      end

      def validate!
        raise "bot_token required" if bot_token.blank?
        raise "signing_secret required" if signing_secret.blank?
      end
    end
  end
end

# Usage
slack_config = MyCompany::Slack::Configuration.new
slack_config.bot_token = ENV["SLACK_BOT_TOKEN"]
slack_config.signing_secret = ENV["SLACK_SIGNING_SECRET"]

processor = FlowChat::Processor.new(self) do |config|
  config.use_gateway MyCompany::Slack::Gateway::BoltJS, slack_config
end
```

### Environment-Based Configuration

```ruby
class MyCompany::Sms::Gateway::Twilio
  def initialize(app, config = nil)
    @app = app
    
    # Use config object or fall back to environment
    if config
      @account_sid = config.account_sid
      @auth_token = config.auth_token
      @from_number = config.from_number
    else
      @account_sid = ENV["TWILIO_ACCOUNT_SID"]
      @auth_token = ENV["TWILIO_AUTH_TOKEN"]
      @from_number = ENV["TWILIO_FROM_NUMBER"]
    end
    
    validate_configuration!
  end

  private

  def validate_configuration!
    required = [@account_sid, @auth_token, @from_number]
    raise "Twilio configuration incomplete" if required.any?(&:blank?)
  end
end
```

## Testing Custom Gateways

### Unit Testing

```ruby
# test/unit/telegram_gateway_test.rb
class TelegramGatewayTest < Minitest::Test
  def setup
    @mock_app = proc { |context| [:text, "Test response", {}, nil] }
    @gateway = MyCompany::Telegram::Gateway::BotAPI.new(@mock_app, "test_token")
  end

  def test_parses_telegram_message
    context = create_mock_context(telegram_payload: {
      "message" => {
        "from" => { "id" => 12345, "username" => "testuser" },
        "text" => "Hello",
        "message_id" => 123
      }
    })

    @gateway.call(context)

    assert_equal "12345", context["request.user_id"]
    assert_equal :telegram, context["request.platform"]
    assert_equal "Hello", context.input
  end

  def test_handles_callback_queries
    context = create_mock_context(telegram_payload: {
      "callback_query" => {
        "from" => { "id" => 12345 },
        "data" => "button_value",
        "id" => "callback123"
      }
    })

    @gateway.call(context)

    assert_equal "button_value", context.input
    assert_equal "callback123", context["telegram.callback_query_id"]
  end

  private

  def create_mock_context(telegram_payload:)
    controller = Minitest::Mock.new
    request = Minitest::Mock.new
    
    request.expect :body, StringIO.new(telegram_payload.to_json)
    controller.expect :request, request
    
    context = FlowChat::Context.new
    context["controller"] = controller
    context
  end
end
```

### Integration Testing

```ruby
# test/integration/telegram_flow_test.rb
class TelegramFlowTest < ActionDispatch::IntegrationTest
  def test_complete_telegram_conversation
    # Simulate Telegram webhook for /start command
    post telegram_webhook_path, 
      params: telegram_message_payload(text: "/start"),
      headers: telegram_headers

    assert_response :success

    # Simulate button press
    post telegram_webhook_path,
      params: telegram_callback_payload(data: "option_1"),
      headers: telegram_headers

    assert_response :success
  end

  private

  def telegram_message_payload(text:)
    {
      message: {
        from: { id: 12345, username: "testuser" },
        text: text,
        message_id: rand(1000),
        date: Time.current.to_i
      }
    }.to_json
  end

  def telegram_headers
    {
      "Content-Type" => "application/json"
    }
  end
end
```

## Advanced Gateway Features

### File Upload Support

```ruby
def handle_file_upload(context, telegram_payload)
  message = telegram_payload["message"]
  
  if message["photo"]
    # Handle photo upload
    photo = message["photo"].last  # Get highest resolution
    file_info = get_telegram_file(photo["file_id"])
    
    context["request.media"] = {
      type: "image",
      file_id: photo["file_id"],
      url: download_telegram_file(file_info["file_path"])
    }
    
    context.input = "$media$"  # Special input to indicate media
    
  elsif message["document"]
    # Handle document upload
    doc = message["document"]
    context["request.media"] = {
      type: "document",
      file_id: doc["file_id"],
      filename: doc["file_name"],
      mime_type: doc["mime_type"]
    }
    
    context.input = "$document$"
  end
end
```

### Real-time Updates

```ruby
class MyCompany::Slack::Gateway::BoltJS
  def call(context)
    # ... standard processing ...
    
    # Send typing indicator for long operations
    if processing_time_estimate > 2.seconds
      send_typing_indicator(context["slack.channel"])
    end
    
    # ... continue processing ...
  end

  private

  def send_typing_indicator(channel)
    slack_client.web_client.conversations_typing(channel: channel)
  end
end
```

### Multi-Message Responses

```ruby
def send_slack_response(type, prompt, choices, media, context)
  channel = context["slack.channel"]
  
  # Send main message
  response = slack_client.web_client.chat_postMessage(
    channel: channel,
    text: prompt
  )
  
  # Send media as separate attachment if present
  if media.present?
    slack_client.web_client.files_upload(
      channels: channel,
      file: media[:url],
      title: media[:filename]
    )
  end
  
  # Add interactive buttons if choices present
  if choices.present?
    slack_client.web_client.chat_update(
      channel: channel,
      ts: response.ts,
      text: prompt,
      blocks: build_slack_blocks(choices)
    )
  end
end
```

## Best Practices

### Error Handling

```ruby
def call(context)
  parse_request(context)
  type, prompt, choices, media = @app.call(context)
  render_response(type, prompt, choices, media, context)
rescue JSON::ParserError => e
  Rails.logger.error "Gateway: Invalid JSON payload: #{e.message}"
  send_error_response("Invalid request format", context)
rescue NetworkError => e
  Rails.logger.error "Gateway: Network error: #{e.message}"
  send_error_response("Service temporarily unavailable", context)
rescue => e
  Rails.logger.error "Gateway: Unexpected error: #{e.class.name}: #{e.message}"
  Rails.logger.debug e.backtrace.join("\n")
  send_error_response("An error occurred", context)
end
```

### Rate Limiting

```ruby
def call(context)
  check_rate_limit(context["request.user_id"])
  # ... continue processing ...
end

private

def check_rate_limit(user_id)
  key = "rate_limit:#{user_id}"
  count = Rails.cache.increment(key, 1, expires_in: 1.minute) || 1
  
  if count > 30  # 30 requests per minute
    raise RateLimitExceeded, "Too many requests"
  end
end
```

### Security

```ruby
def call(context)
  verify_webhook_signature(context)
  # ... continue processing ...
end

private

def verify_webhook_signature(context)
  signature = context.controller.request.headers["X-Platform-Signature"]
  payload = context.controller.request.body.read
  
  expected = generate_signature(payload, @webhook_secret)
  
  unless secure_compare(signature, expected)
    raise SecurityError, "Invalid webhook signature"
  end
end

def secure_compare(a, b)
  return false unless a.bytesize == b.bytesize
  
  l = a.unpack("C*")
  r = b.unpack("C*")
  
  l.zip(r).reduce(0) { |sum, (x, y)| sum | (x ^ y) } == 0
end
```

## Publishing Your Gateway

### Gem Structure

If you're building a reusable gateway, structure it as a gem:

```
my_platform_gateway/
├── lib/
│   └── flow_chat/
│       └── my_platform/
│           ├── gateway.rb
│           ├── configuration.rb
│           ├── middleware/
│           └── renderer.rb
├── spec/
├── README.md
└── my_platform_gateway.gemspec
```

### Documentation

Document your gateway's:
- Installation instructions
- Configuration options
- Platform-specific features
- Middleware stack
- Testing helpers

### Examples

Provide working examples:

```ruby
# examples/basic_controller.rb
class MyPlatformController < ApplicationController
  def webhook
    processor = FlowChat::Processor.new(self) do |config|
      config.use_gateway FlowChat::MyPlatform::Gateway, platform_config
      config.use_session_store FlowChat::Session::CacheSessionStore
    end

    processor.run WelcomeFlow, :start
  end
end
```

Custom gateways make FlowChat incredibly powerful and flexible. With this foundation, you can integrate virtually any conversational platform into FlowChat's unified framework. 
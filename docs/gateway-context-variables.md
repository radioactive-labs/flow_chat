# Gateway Context Variables

This document describes all context variables set by each gateway in FlowChat.

## All Context Variables

| Variable | USSD Nalo | HTTP Simple | WhatsApp Cloud API | Telegram Bot API | Intercom API | Description |
|----------|-----------|-------------|-------------------|------------------|--------------|-------------|
| **Common Variables** |
| `request.id` | ✓ Session ID | ✓ From user_params | ✓ Phone number | ✓ Chat ID | ✓ Conversation ID | Unique identifier for the session/conversation |
| `request.user_id` | ✓ = msisdn | ✓ From user_params | ✓ Phone number | ✓ Telegram user ID | ✓ Contact ID | User/contact identifier |
| `request.user_name` | ✗ | ✓ (optional) | ✓ (optional) | ✓ First + Last name | ✓ (optional) | User's display name |
| `request.username` | ✗ | ✗ | ✗ | ✓ Telegram username | ✗ | Telegram @username |
| `request.msisdn` | ✓ | ✓ (optional) | ✓ | ✗ | ✓ (optional) | E.164 phone number |
| `request.email` | ✗ | ✓ (optional) | ✗ | ✗ | ✓ (optional) | User email |
| `request.message_id` | ✓ UUID | ✓ UUID | ✓ WhatsApp ID | ✓ Telegram msg ID | ✓ (optional) | Message identifier |
| `request.timestamp` | ✓ Current | ✓ Current | ✓ Current | ✓ From message | ✓ Current | ISO8601 timestamp |
| `request.gateway` | ✓ `:nalo` | ✓ `:http_simple` | ✓ `:whatsapp_cloud_api` | ✓ `:telegram_bot_api` | ✓ `:intercom_api` | Gateway name |
| `request.platform` | ✓ `:ussd` | ✓ `:http` | ✓ `:whatsapp` | ✓ `:telegram` | ✓ `:intercom` | Platform type |
| `request.body` | ✓ | ✓ | ✓ | ✓ | ✓ | Raw request body (stringified keys) |
| `request.input` | ✓ Text | ✓ Text | ✓ Varies⁴ | ✓ Varies⁶ | ✓ Text/nil⁵ | User's input message |
| **WhatsApp-Specific** |
| `request.location` | ✗ | ✗ | ✓ | ✓ | ✗ | Location data (when input is `"$location$"`) |
| `request.media` | ✗ | ✗ | ✓ | ✓ | ✗ | Media metadata (when input is `"$media$"`) |
| `request.contact` | ✗ | ✗ | ✗ | ✓ | ✗ | Contact data (when input is `"$contact$"`) |
| `whatsapp.business.phone_number` | ✗ | ✗ | ✓ | ✗ | ✗ | Business phone number (E.164) |
| `whatsapp.business.phone_number_id` | ✗ | ✗ | ✓ | ✗ | ✗ | WhatsApp phone number ID |
| `whatsapp.client` | ✗ | ✗ | ✓ | ✗ | ✗ | WhatsApp client instance |
| **Telegram-Specific** |
| `telegram.client` | ✗ | ✗ | ✗ | ✓ | ✗ | Telegram client instance |
| `telegram.chat_type` | ✗ | ✗ | ✗ | ✓ | ✗ | Chat type (private, group, supergroup, channel) |
| `telegram.callback_query_id` | ✗ | ✗ | ✗ | ✓ (callbacks) | ✗ | Callback query ID for inline keyboard responses |
| `telegram.original_message_id` | ✗ | ✗ | ✗ | ✓ (callbacks) | ✗ | Original message ID that triggered callback |
| **HTTP-Specific** |
| `http.method` | ✗ | ✓ | ✗ | ✗ | ✗ | HTTP method (GET/POST) |
| `http.path` | ✗ | ✓ | ✗ | ✗ | ✗ | Request path |
| `http.user_agent` | ✗ | ✓ | ✗ | ✗ | ✗ | User agent header |
| **Intercom-Specific** |
| `intercom.client` | ✗ | ✗ | ✗ | ✗ | ✓ | Intercom client instance |
| `intercom.topic` | ✗ | ✗ | ✗ | ✗ | ✓ | Webhook event type |


## Accessing Variables in Flows

```ruby
class MyFlow < FlowChat::Flow
  def start
    # Common variables (all gateways)
    user_id = app.context["request.user_id"]
    user_name = app.context["request.user_name"]  # Available from WhatsApp, Intercom, HTTP (optional)
    msisdn = app.context["request.msisdn"]        # Available from USSD, WhatsApp, HTTP (optional)
    email = app.context["request.email"]          # Available from HTTP (optional)
    platform = app.context["request.platform"]
    input = app.context["request.input"]

    # Or use convenience methods
    user_id = app.user_id
    platform = app.platform
    input = app.input

    # Platform-specific variables
    case app.platform
    when :whatsapp
      client = app.context["whatsapp.client"]

      # Handle special input types
      if input == "$location$"
        location = app.context["request.location"]
        lat = location[:latitude]
        lng = location[:longitude]
      end

    when :telegram
      client = app.context["telegram.client"]
      chat_type = app.context["telegram.chat_type"]
      username = app.context["request.username"]  # @username

      # Handle special input types
      case input
      when "$location$"
        location = app.context["request.location"]
        lat = location["latitude"]
        lng = location["longitude"]
      when "$media$"
        media = app.context["request.media"]
        file_id = media[:file_id]
        media_type = media[:type]  # :photo, :document, :voice
      when "$contact$"
        contact = app.context["request.contact"]
        phone = contact[:phone_number]
      end

    when :intercom
      topic = app.context["intercom.topic"]
      client = app.context["intercom.client"]

      # Handle events without messages
      if input.nil?
        # Event without user message (e.g., admin-initiated)
      end

    when :http
      method = app.context["http.method"]
      user_agent = app.context["http.user_agent"]

    when :ussd
      msisdn = app.context["request.msisdn"]
    end
  end
end
```

## Notes

⁴ **WhatsApp input**: Text for text messages, `"$location$"` for location, `"$media$"` for media (image, document, audio, video, sticker), `"$contact$"` for shared contacts, or button/list reply IDs.

⁵ **Intercom input**: Text content or `nil` for events without user messages.

⁶ **Telegram input**: Text for text messages, callback data for inline keyboard responses, `"$location$"` for location, `"$media$"` for media (photo, video, audio, document, voice, sticker), `"$contact$"` for shared contacts.

## Media Type Reference

Both WhatsApp and Telegram set `request.media` with a `:type` symbol when media is received:

| Media Type | WhatsApp | Telegram | Additional Fields |
|------------|----------|----------|-------------------|
| `:image` / `:photo` | ✓ `:image` | ✓ `:photo` | id/file_id, mime_type, width, height |
| `:video` | ✓ | ✓ | id/file_id, mime_type, duration, width, height |
| `:audio` | ✓ | ✓ | id/file_id, mime_type, duration, title, performer |
| `:voice` | ✗ | ✓ | file_id, mime_type, duration |
| `:document` | ✓ | ✓ | id/file_id, mime_type, filename |
| `:sticker` | ✓ | ✓ | id/file_id, emoji, set_name, is_animated |

### Accessing Media in Flows

FlowChat provides constants for special input markers:

```ruby
FlowChat::Input::LOCATION  # "$location$"
FlowChat::Input::MEDIA     # "$media$"
FlowChat::Input::CONTACT   # "$contact$"
FlowChat::Input::START     # "$start$" (session marker)
```

Example usage:

```ruby
case app.input
when FlowChat::Input::MEDIA
  media = app.context["request.media"]

  case media[:type]
  when :photo, :image
    file_id = media[:file_id] || media[:id]
  when :video
    duration = media[:duration]
  when :document
    filename = media[:file_name] || media[:filename]
  when :sticker
    emoji = media[:emoji]
  end

when FlowChat::Input::LOCATION
  location = app.context["request.location"]
  lat, lng = location["latitude"], location["longitude"]

when FlowChat::Input::CONTACT
  contact = app.context["request.contact"]
  phone = contact[:phone_number]
end
```

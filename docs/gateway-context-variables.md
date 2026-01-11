# Gateway Context Variables

This document describes all context variables set by each gateway in FlowChat.

## All Context Variables

| Variable | USSD Nalo | HTTP Simple | WhatsApp Cloud API | Intercom API | Description |
|----------|-----------|-------------|-------------------|--------------|-------------|
| **Common Variables** |
| `request.id` | ✓ Session ID | ✓ From user_params | ✓ Phone number | ✓ Conversation ID | Unique identifier for the session/conversation |
| `request.user_id` | ✓ = msisdn | ✓ From user_params | ✓ = msisdn | ✓ Contact ID | User/contact identifier |
| `request.msisdn` | ✓ | ✓ (optional) | ✓ | ✗ | E.164 phone number |
| `request.email` | ✗ | ✓ (optional) | ✗ | ✗ | User email |
| `request.message_id` | ✓ UUID | ✓ UUID | ✓ WhatsApp ID | ✓ (optional) | Message identifier |
| `request.timestamp` | ✓ Current | ✓ Current | ✓ Current³ | ✓ Current | ISO8601 timestamp |
| `request.gateway` | ✓ `:nalo` | ✓ `:http_simple` | ✓ `:whatsapp_cloud_api` | ✓ `:intercom_api` | Gateway name |
| `request.platform` | ✓ `:ussd` | ✓ `:http` | ✓ `:whatsapp` | ✓ `:intercom` | Platform type |
| `request.body` | ✓ | ✓ | ✓ | ✓ | Raw request body (stringified keys) |
| `request.input` | ✓ Text | ✓ Text | ✓ Varies⁴ | ✓ Text/nil⁵ | User's input message |
| **WhatsApp-Specific** |
| `request.location` | ✗ | ✗ | ✓ | ✗ | Location data (when input is `"$location$"`) |
| `request.media` | ✗ | ✗ | ✓ | ✗ | Media metadata (when input is `"$media$"`) |
| `whatsapp.contact.name` | ✗ | ✗ | ✓ | ✗ | Contact's profile name |
| `whatsapp.business.phone_number` | ✗ | ✗ | ✓ | ✗ | Business phone number (E.164) |
| `whatsapp.business.phone_number_id` | ✗ | ✗ | ✓ | ✗ | WhatsApp phone number ID |
| `whatsapp.client` | ✗ | ✗ | ✓ | ✗ | WhatsApp client instance |
| **HTTP-Specific** |
| `http.method` | ✗ | ✓ | ✗ | ✗ | HTTP method (GET/POST) |
| `http.path` | ✗ | ✓ | ✗ | ✗ | Request path |
| `http.user_agent` | ✗ | ✓ | ✗ | ✗ | User agent header |
| **Intercom-Specific** |
| `intercom.client` | ✗ | ✗ | ✗ | ✓ | Intercom client instance |
| `intercom.topic` | ✗ | ✗ | ✗ | ✓ | Webhook event type |


## Accessing Variables in Flows

```ruby
class MyFlow < FlowChat::Flow
  def start
    # Common variables (all gateways)
    user_id = app.context["request.user_id"]
    platform = app.context["request.platform"]
    input = app.context["request.input"]

    # Or use convenience methods
    user_id = app.user_id
    platform = app.platform
    input = app.input

    # Platform-specific variables
    case app.platform
    when :whatsapp
      name = app.context["whatsapp.contact.name"]
      client = app.context["whatsapp.client"]

      # Handle special input types
      if input == "$location$"
        location = app.context["request.location"]
        lat = location[:latitude]
        lng = location[:longitude]
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

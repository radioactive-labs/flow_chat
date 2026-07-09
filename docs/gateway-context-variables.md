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

⁴ **WhatsApp input**: The turn's text — the message text, a media caption, or a button/list reply ID. `""` for a structured turn (location, media, contact) that carries no text. The structured payload itself is on `request.media`/`request.location`/`request.contact`.

⁵ **Intercom input**: The message text (media caption / body), or `""`/`nil` for turns without text.

⁶ **Telegram input**: The turn's text — message text, callback data, or a media caption. `""` for a structured turn (location, media, contact) with no text.

> **Note:** `context.input` is always plain text now. The old `"$media$"`/`"$location$"`/`"$contact$"` sentinels have been removed — a structured turn with no text sets `input` to `""` and carries its payload on `request.media`/`request.location`/`request.contact`. In flows, read `app.input` (a `FlowChat::Input`) or its accessors; see below.

## Media Type Reference

WhatsApp, Telegram, Intercom, and HTTP all set `request.media` when inbound media is received (USSD is text-only and never sets media). WhatsApp and Telegram carry a single item, while Intercom may carry several (one per attachment). HTTP callers submit inbound media via the `media_url` request param (with optional `media_type` and `mime_type`).

The raw `:type` in the table below is the platform-native value. When you access media through `app.media` (a list of `FlowChat::Media`), each item's `type` is a **normalized** value (`:photo` → `:image`, `:voice` → `:audio`) and `raw_type` returns the native value.

| Media Type | WhatsApp | Telegram | Additional Fields |
|------------|----------|----------|-------------------|
| `:image` / `:photo` | ✓ `:image` | ✓ `:photo` | id/file_id, mime_type, width, height |
| `:video` | ✓ | ✓ | id/file_id, mime_type, duration, width, height |
| `:audio` | ✓ | ✓ | id/file_id, mime_type, duration, title, performer |
| `:voice` | ✗ | ✓ | file_id, mime_type, duration |
| `:document` | ✓ | ✓ | id/file_id, mime_type, filename |
| `:sticker` | ✓ | ✓ | id/file_id, emoji, set_name, is_animated |

### Accessing the Turn in Flows

Every turn is a `FlowChat::Input` value object, available as `app.input`. A turn
has two independent axes: **text** and an optional **attachment**. Text and media
can arrive together (a captioned photo); `location` and `contact` always arrive on
their own. The value object exposes both, and `app` provides shortcut accessors.

```ruby
# Text is always safe to read — "" when the turn carried no text (e.g. a
# caption-less photo). It holds the caption/body when media is attached.
message = app.text

# Branch on the attachment kind, not on a magic input value:
case app.attachment_type
when :media
  # app.media is ALWAYS a list — iterate, so you never drop extra attachments
  app.media.each do |item|
    item.type        # canonical: :image, :video, :audio, :document, :sticker
    item.raw_type    # platform-native: e.g. :photo/:voice on Telegram
    item.mime_type
    item.filename
    url   = item.url        # a fetchable URL
    bytes = item.download   # the raw file bytes
  end
when :location
  lat = app.location[:latitude]
  lng = app.location[:longitude]
when :contact
  name = app.contact[:name]
end

app.contact_name   # the sender's display name (distinct from a shared contact)
```

Accessors (all shortcuts to the `app.input` value object):

- `app.text` → the turn's text (typed message or the caption/body sent with an attachment). Always a string; `""` when there is no text.
- `app.attachment_type` → `:media` / `:location` / `:contact` / `nil` — the discriminator to branch on.
- `app.attachment` → the payload of `attachment_type`: the media **list**, or the location / contact hash, or `nil`.
- `app.media` → **always** an `Array<FlowChat::Media>` (empty when none) — a list even on single-media platforms, so you iterate uniformly and never silently drop the extra attachments a message can carry.
- `media` item `type` → canonical (`:image`, `:video`, `:audio`, `:document`, `:sticker`); `raw_type` → platform-native (Telegram's `:photo`/`:voice`). `url` resolves a fetchable URL per platform (WhatsApp `get_media_url`, Telegram `getFile`, Intercom/HTTP direct URL); `download` returns the raw bytes.
- `app.location` → the location hash, or `nil`.
- `app.contact` → the shared contact card hash, or `nil`.
- `app.contact_name` → the sender's display name.

The `FlowChat::Input` object also behaves like its text for string operations, so
validators and transforms read naturally — and can inspect the attachment:

```ruby
app.screen(:photo) do |prompt|
  prompt.ask "Send your ID photo",
    validate: ->(input) { "Please attach a photo" unless input.media.any? }
end

app.screen(:name) do |prompt|
  # input.strip / input.blank? etc. operate on the text
  prompt.ask "Your name?", transform: ->(input) { input.strip.titleize }
end
```

A turn is considered answered (`input.submitted?`) when it has text **or** an
attachment — so a caption-less photo still satisfies a screen.

#### Lower-level access

Prefer the accessors above. The raw request hashes remain available if you need them:

```ruby
app.context["request.media"]     # raw Hash, or Array for Intercom
app.context["request.location"]
app.context["request.contact"]
```

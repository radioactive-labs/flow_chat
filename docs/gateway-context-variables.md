# Gateway context variables

Every gateway parses its platform's webhook into a common set of context values. Flows and middleware read these instead of platform-specific request shapes, which is what lets one flow run everywhere. This document lists what each gateway sets.

## All context variables

| Variable | USSD Nalo | HTTP Simple | WhatsApp Cloud API | Telegram Bot API | Intercom API | Description |
|----------|-----------|-------------|-------------------|------------------|--------------|-------------|
| **Common** |
| `request.id` | Session id | From user_params | Phone number | Chat id | Conversation id | Session or conversation identifier |
| `request.user_id` | = msisdn | From user_params | Phone number | Telegram user id | Contact id | Stable per-user identifier |
| `request.user_name` | none | optional | optional | First and last name | optional | Sender display name |
| `request.username` | none | none | none | Telegram @username | none | Telegram username |
| `request.msisdn` | set | optional | set | none | optional | E.164 phone number |
| `request.email` | none | optional | none | none | optional | User email |
| `request.message_id` | UUID | UUID | WhatsApp id | Telegram msg id | optional | Message identifier |
| `request.timestamp` | Current | Current | Current | From message | Current | ISO8601 timestamp |
| `request.gateway` | `:nalo` | `:http_simple` | `:whatsapp_cloud_api` | `:telegram_bot_api` | `:intercom_api` | Gateway symbol |
| `request.platform` | `:ussd` | `:http` | `:whatsapp` | `:telegram` | `:intercom` | Platform symbol |
| `request.body` | set | set | set | set | set | Raw request body, string keys |
| `request.input` | Text | Text | Text (note 1) | Text (note 2) | Text or nil (note 3) | The turn's text |
| **Structured attachments** |
| `request.location` | none | none | set | set | none | Location payload |
| `request.media` | none | via `media_url` | set | set | set (may be several) | Media metadata |
| `request.contact` | none | none | none | set | none | Contact payload |
| **WhatsApp** |
| `whatsapp.business.phone_number` | | | E.164 business number | | | |
| `whatsapp.business.phone_number_id` | | | WhatsApp phone number id | | | |
| `whatsapp.client` | | | client instance | | | |
| **Telegram** |
| `telegram.client` | | | | client instance | | |
| `telegram.chat_type` | | | | private, group, supergroup, channel | | |
| `telegram.callback_query_id` | | | | on callbacks | | |
| `telegram.original_message_id` | | | | on callbacks | | |
| **HTTP** |
| `http.method` | | GET or POST | | | | |
| `http.path` | | Request path | | | | |
| `http.user_agent` | | User agent header | | | | |
| **Intercom** |
| `intercom.client` | | | | | client instance | |
| `intercom.topic` | | | | | Webhook event type | |

Notes on `request.input`:

1. WhatsApp: the message text, a media caption, or a button/list reply id. `""` for a structured turn (location, media, contact) that carries no text.
2. Telegram: the message text, callback data, or a media caption. `""` for a structured turn with no text.
3. Intercom: the message text or body, or `""`/`nil` for turns without text.

`context.input` is always plain text. There are no `"$media$"`/`"$location$"`/`"$contact$"` sentinel values: a structured turn with no text sets `input` to `""` and carries its payload on `request.media`, `request.location`, or `request.contact`. In flows, read `app.input` (a `FlowChat::Input`) or its accessors, described below.

## Reading the turn in a flow

Prefer the accessors on `app` over reading context keys directly. Every turn is a `FlowChat::Input` value object with two independent axes: text and an optional attachment. Text and media can arrive together (a captioned photo); location and contact arrive on their own.

```ruby
class MyFlow < FlowChat::Flow
  def start
    # Identity and platform, available on every platform.
    user_id  = app.user_id
    platform = app.platform
    msisdn   = app.msisdn

    # The turn's text. Always a string, "" when the turn carried no text.
    message = app.text

    # Branch on the attachment kind, not on a magic input value.
    case app.attachment_type
    when :media
      app.media.each do |item|   # always a list; iterate so you never drop extra attachments
        item.type       # canonical: :image, :video, :audio, :document, :sticker
        item.raw_type   # platform-native: :photo or :voice on Telegram
        item.mime_type
        item.filename
        link  = item.url        # a fetchable URL, or nil
        bytes = item.download   # the raw file bytes, or nil
      end
    when :location
      lat = app.location[:latitude]
      lng = app.location[:longitude]
    when :contact
      name = app.contact[:name]
    end
  end
end
```

Accessors, all shortcuts to the `app.input` value object:

- `app.text`: the turn's text, or the caption sent with an attachment. Always a string, `""` when there is no text.
- `app.attachment_type`: `:media`, `:location`, `:contact`, or `nil`, the discriminator to branch on.
- `app.attachment`: the payload of `attachment_type` (the media list, the location hash, the contact hash, or `nil`).
- `app.media`: always an `Array<FlowChat::Media>` (empty when none), a list even on single-media platforms, so you iterate uniformly.
- `app.location`: the location hash, or `nil`.
- `app.contact`: the shared contact card hash, or `nil`.
- `app.contact_name`: the sender's display name (distinct from a shared contact card).

## Media

WhatsApp, Telegram, Intercom, and HTTP set `request.media` for inbound media (USSD is text-only and never sets it). WhatsApp and Telegram carry a single item; Intercom may carry several, one per attachment. HTTP callers submit inbound media through the `media_url` request param, with optional `media_type` and `mime_type`.

A `FlowChat::Media` item's `type` is a normalized value; `raw_type` is the platform-native value. The normalization maps `:photo` to `:image` and `:voice` to `:audio`, so `type` is one of `:image`, `:video`, `:audio`, `:document`, `:sticker`.

| Media type | WhatsApp | Telegram | Fields |
|------------|----------|----------|--------|
| `:image` (Telegram `:photo`) | yes | yes | id or file_id, mime_type, width, height |
| `:video` | yes | yes | id or file_id, mime_type, duration, width, height |
| `:audio` | yes | yes | id or file_id, mime_type, duration, title, performer |
| `:voice` | no | yes | file_id, mime_type, duration |
| `:document` | yes | yes | id or file_id, mime_type, filename |
| `:sticker` | yes | yes | id or file_id, emoji, set_name, is_animated |

`item.url` resolves a fetchable URL per platform (WhatsApp `get_media_url`, Telegram `getFile`, Intercom and HTTP use the direct URL). `item.download` returns the raw bytes.

### Inspecting attachments in validate and transform

The `FlowChat::Input` object behaves like its text for string operations, so validators and transforms read naturally, and it also exposes the attachment:

```ruby
app.screen(:photo) do |prompt|
  prompt.ask "Send your ID photo",
    validate: ->(input) { "Please attach a photo" unless input.media.any? }
end

app.screen(:name) do |prompt|
  prompt.ask "Your name?", transform: ->(input) { input.strip.titleize }
end
```

A turn counts as answered (`input.submitted?`) when it has text or an attachment, so a caption-less photo still satisfies a screen.

### What a screen should return

`prompt.ask` and `prompt.select` return a string (the text, or your `transform`'s result), and that string is what gets stored as the screen's answer. Return those from screen blocks.

`prompt.user_input` is the raw `FlowChat::Input` object, useful inside a `validate` or `transform` when you want the attachment, but avoid returning it as a screen's value:

```ruby
# Good: persists a string.
name = app.screen(:name) { |prompt| prompt.ask "Your name?" }

# Avoid: persists the whole Input object into the session store.
raw = app.screen(:raw) { |prompt| prompt.user_input }
```

Whatever a screen returns is stored in the session and serialized by the store (`CacheSessionStore` uses `Marshal`). A `FlowChat::Media` serializes without its live platform client, so a media object deserialized from the session has no client and its `url` and `download` return `nil` rather than raising. Fetch media during the turn it arrives, while the client is present; do not rely on downloading it from a stored answer on a later turn.

### Lower-level access

The raw request hashes remain available if you need them, but prefer the accessors above:

```ruby
app.context["request.media"]     # raw Hash, or Array for Intercom
app.context["request.location"]
app.context["request.contact"]
```

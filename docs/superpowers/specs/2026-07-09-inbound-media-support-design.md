# Inbound Media Support — Design

**Date:** 2026-07-09
**Status:** Approved (design)

## Problem

FlowChat has complete *outbound* media support (`ask`/`say`/`select` with `media:`,
per-platform renderers, WhatsApp `upload_media`/`download_media`/`get_media_url`).

*Inbound* media is broken in the middle of the pipe:

- The **WhatsApp** and **Telegram** gateways already parse incoming media into
  `context["request.media"]` (and `request.location`, `request.contact`), and set
  `context.input` to the sentinels `FlowChat::Input::MEDIA` (`$media$`) /
  `FlowChat::Input::LOCATION` (`$location$`).
- But `FlowChat::App#media`, `#location`, and `#contact_name` return a hardcoded
  `nil` (`lib/flow_chat/app.rb:66-76`), so parsed data never reaches a flow.
- The **Intercom** and **HTTP** gateways do not parse inbound media at all.
- **USSD** is text-only and out of scope.

## Goals

1. Expose inbound media to flows via `app.media`, returning both metadata **and** a
   way to fetch the bytes/URL.
2. Also expose the co-located, equally-stranded `app.location` and contact data.
3. Add inbound media parsing to the Intercom and HTTP gateways (USSD skipped).
4. Keep outbound behavior unchanged (parity only).

## Non-Goals

- No new outbound features (local-file auto-upload, new platforms/types).
- No USSD inbound media.
- No change to the `$media$`/`$location$` sentinel input mechanism.

## Approach

A dedicated `FlowChat::Media` value object owns all cross-platform inbound-media
normalization. `app.media` wraps `context["request.media"]` in it. Per-platform
quirks (WhatsApp media-id vs Telegram file_id vs Intercom/HTTP direct URL) live in
this single testable class, delegating to existing client download methods where
they exist.

Rejected alternatives:
- **Hash + helper methods on `App`** — hash isn't self-describing; platform
  branching leaks into `App`.
- **`download_inbound` on each client** — parallel code in every client and still
  needs an app-level entry point.

## Components

### 1. `FlowChat::Media` (new — `lib/flow_chat/media.rb`)

A value object wrapping one inbound media item.

- **Construction:** `FlowChat::Media.new(data, platform:, client:)` where `data` is
  the raw `context["request.media"]` hash. `client` may be `nil` for URL-based
  platforms (HTTP).
- **Readers:** `type`, `mime_type`, `caption`, `filename`, `id` (WhatsApp),
  `file_id` (Telegram), and `[]` for raw-hash access. Missing keys return `nil` —
  media hashes differ by platform and this is expected, not defensive.
- **`#url`** — resolves a fetchable URL:
  - WhatsApp: `client.get_media_url(id)`
  - Telegram: `client.file_url(file_id)` (new client method)
  - Intercom / HTTP: the direct `data[:url]`
- **`#download`** — returns the raw bytes:
  - WhatsApp: `client.download_media(id)`
  - Telegram: `client.download_file(file_id)` (new client method)
  - URL-based (Intercom/HTTP): plain HTTP GET of `#url`

Platform is selected by a simple `case` on `platform`. Note the type vocabulary
differs by platform and is preserved as-parsed (WhatsApp: `:image, :document,
:audio, :video, :sticker`; Telegram: `:photo, :video, :audio, :document, :voice,
:sticker`). No forced normalization of `type` — documented, not hidden.

### 2. `FlowChat::App` wiring (`lib/flow_chat/app.rb`)

Replace the `nil` stubs. Inbound media is normalized to a list because a single
message can carry multiple media items on some platforms (Intercom attachments),
while WhatsApp/Telegram carry exactly one:

- `media_items` → `Array<FlowChat::Media>`. Reads `context["request.media"]`, which
  may be a single hash (WhatsApp/Telegram) or an array of hashes (Intercom, HTTP).
  Normalizes shape (`raw.is_a?(Array) ? raw : [raw]`), maps each to
  `FlowChat::Media`, returns `[]` when none. This is the one place shape is
  normalized — the WhatsApp/Telegram gateways are **not** changed.
- `media` → `media_items.first` (the ergonomic single-media accessor; `nil` when
  none). Common case for WhatsApp/Telegram flows.
- `location` → returns `context["request.location"]` (hash or `nil`).
- `contact_name` → returns `context["request.user_name"]` (the sender's display
  name, as set by the gateways).
- `contact` → returns `context["request.contact"]` (a contact card the user
  *shared*, distinct from the sender; `nil` when none).

Each `FlowChat::Media` is built with the platform client chosen from context
(`whatsapp.client` / `telegram.client` / `intercom.client`; `nil` for HTTP). A small
private `media_client` helper maps platform → context client key.

### 3. Telegram client (`lib/flow_chat/telegram/client.rb`)

Telegram requires a `getFile` round-trip before download. Add:

- `get_file(file_id)` — calls the `getFile` API method, returns the file metadata
  (including `file_path`).
- `file_url(file_id)` — resolves to
  `https://api.telegram.org/file/bot<token>/<file_path>`.
- `download_file(file_id)` — GETs `file_url` and returns the bytes.

### 4. Intercom gateway inbound parsing (`lib/flow_chat/intercom/gateway/intercom_api.rb`)

In the latest-user-message extraction path, parse `attachments` (an **array** —
Intercom conversation parts and the conversation `source` each carry
`attachments` with `name`, `url`, `content_type`, `type`). Map **all** attachments:

```ruby
media = attachments.map do |a|
  {
    type: intercom_media_type(a["content_type"]),  # image/* → :image, else :document
    url: a["url"],
    mime_type: a["content_type"],
    filename: a["name"]
  }
end
context["request.media"] = media   # array, one entry per attachment
context.input = FlowChat::Input::MEDIA
```

A single Intercom message legitimately carries multiple attachments, so the array
form is required here. `intercom_media_type` maps `content_type`: `image/*` →
`:image`, `video/*` → `:video`, `audio/*` → `:audio`, otherwise `:document`.

### 5. HTTP gateway inbound parsing (`lib/flow_chat/http/gateway/simple.rb`)

Accept media from request params. Contract: a `media_url` param (optionally with
`media_type` and `mime_type`), or a nested `media` hash. When present:

```ruby
context["request.media"] = {
  type: (params["media_type"] || :document).to_sym,
  url: params["media_url"],
  mime_type: params["mime_type"]
}
context.input = FlowChat::Input::MEDIA  # unless a text input is also present
```

Text input still takes precedence when both are supplied, preserving current
behavior for existing HTTP callers.

## Data Flow (inbound)

```
Webhook → Gateway parses payload → context["request.media"] = {...}
        → context.input = "$media$"
        → Session::Middleware → Executor → Flow
Flow: app.media_items → [FlowChat::Media(data, platform, client), ...]  (normalized)
      app.media       → media_items.first  (single-media convenience)
      app.media.download → client.download_media / download_file / GET url
```

## Error Handling

- `app.media` returns `nil` when no inbound media is present.
- `Media#url` / `#download` surface client/network errors the same way existing
  client methods do (WhatsApp client logs and returns `nil` on API error; Telegram
  download raises on non-success, consistent with that client's style).
- Missing metadata keys return `nil` (platforms legitimately omit fields).

## Testing

- **Unit — `FlowChat::Media`** (`test/unit/media_test.rb`): readers; `url`/`download`
  dispatch per platform (WhatsApp id, Telegram file_id, URL-based) with mocked clients.
- **Unit — Telegram client** (`test/unit/telegram/client_test.rb`): `get_file`,
  `file_url`, `download_file` against a stubbed API.
- **Unit — `App` normalization** (in `media_test.rb` or app test): `media_items`
  returns `[]` with no media, one item for a single hash, and N items for an array;
  `media` returns the first item or `nil`.
- **Integration** (`test/integration/media_support_test.rb`): extend with inbound
  cases — `app.media` returns a populated `FlowChat::Media` for WhatsApp, Telegram,
  Intercom, and HTTP; Intercom with multiple attachments yields
  `app.media_items.size == 2`; `app.location` and `app.contact` populated where
  applicable; `app.media` is `nil` and `app.media_items` is `[]` for plain text.

## Files

- Create: `lib/flow_chat/media.rb`, `test/unit/media_test.rb`
- Modify: `lib/flow_chat.rb` (require new file), `lib/flow_chat/app.rb`,
  `lib/flow_chat/telegram/client.rb`,
  `lib/flow_chat/intercom/gateway/intercom_api.rb`,
  `lib/flow_chat/http/gateway/simple.rb`,
  `test/integration/media_support_test.rb`, `test/unit/telegram/client_test.rb`

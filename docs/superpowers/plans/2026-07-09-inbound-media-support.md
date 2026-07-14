# Inbound Media Support Implementation Plan

> **Status: Superseded (historical).** This plan reflects the original approach. The
> shipped implementation diverged: input sentinels (`FlowChat::Input::MEDIA`/`$media$`,
> etc.) were replaced by a `FlowChat::Input` turn value object (`context.input` is
> always plain text), and `app.media` is now **always** an `Array<FlowChat::Media>`
> (the `media_items` accessor described below was dropped). See
> `docs/gateway-context-variables.md` for the current API.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose inbound media (and location/contact) to flows across WhatsApp, Telegram, Intercom, and HTTP via a `FlowChat::Media` value object with metadata plus `url`/`download`.

**Architecture:** A new `FlowChat::Media` value object encapsulates all cross-platform inbound-media quirks (WhatsApp media-id, Telegram file_id, Intercom/HTTP direct URL) behind `#url`/`#download`. `App` normalizes `context["request.media"]` (single hash or array) into `Array<FlowChat::Media>` via `media_items`, with `media` as the first-item convenience. The Telegram client gains `getFile`-based download; the Intercom and HTTP gateways gain inbound media parsing (Intercom supports multiple attachments per message).

**Tech Stack:** Ruby, Zeitwerk autoloading, Minitest (minitest/mock), Net::HTTP.

**User Verification:** NO — no user verification required.

---

### Task 1: `FlowChat::Media` value object

**Goal:** A value object wrapping one inbound media item, exposing metadata plus per-platform `url`/`download`.

**Files:**
- Create: `lib/flow_chat/media.rb`
- Test: `test/unit/media_test.rb`

**Acceptance Criteria:**
- [ ] Readers expose `type`, `mime_type`, `caption`, `filename` (handles `:filename` and `:file_name`), `id`, `file_id`, `[]`, `to_h`.
- [ ] `#url` dispatches: WhatsApp → `client.get_media_url(id)`; Telegram → `client.file_url(file_id)`; else → `data[:url]`.
- [ ] `#download` dispatches: WhatsApp → `client.download_media(id)`; Telegram → `client.download_file(file_id)`; else → HTTP GET of `#url`.
- [ ] Autoloads as `FlowChat::Media` with no explicit require (Zeitwerk).

**Verify:** `ruby -Itest test/unit/media_test.rb -v` → all pass

**Steps:**

- [ ] **Step 1: Write the failing test**

Create `test/unit/media_test.rb`:

```ruby
require "test_helper"

class MediaTest < Minitest::Test
  def test_metadata_readers
    m = FlowChat::Media.new(
      {type: :image, mime_type: "image/jpeg", caption: "hi", filename: "a.jpg", id: "MID"},
      platform: :whatsapp
    )
    assert_equal :image, m.type
    assert_equal "image/jpeg", m.mime_type
    assert_equal "hi", m.caption
    assert_equal "a.jpg", m.filename
    assert_equal "MID", m.id
    assert_equal "image/jpeg", m[:mime_type]
  end

  def test_filename_falls_back_to_file_name_key
    m = FlowChat::Media.new({type: :document, file_name: "doc.pdf"}, platform: :telegram)
    assert_equal "doc.pdf", m.filename
  end

  def test_whatsapp_url_and_download_delegate_to_client
    client = Minitest::Mock.new
    client.expect(:get_media_url, "https://cdn/x.jpg", ["MID"])
    client.expect(:download_media, "BYTES", ["MID"])
    m = FlowChat::Media.new({type: :image, id: "MID"}, platform: :whatsapp, client: client)
    assert_equal "https://cdn/x.jpg", m.url
    assert_equal "BYTES", m.download
    client.verify
  end

  def test_telegram_url_and_download_delegate_to_client
    client = Minitest::Mock.new
    client.expect(:file_url, "https://tg/file.jpg", ["FID"])
    client.expect(:download_file, "TGBYTES", ["FID"])
    m = FlowChat::Media.new({type: :photo, file_id: "FID"}, platform: :telegram, client: client)
    assert_equal "https://tg/file.jpg", m.url
    assert_equal "TGBYTES", m.download
    client.verify
  end

  def test_url_based_platform_uses_direct_url
    m = FlowChat::Media.new({type: :image, url: "https://intercom/a.png"}, platform: :intercom)
    assert_equal "https://intercom/a.png", m.url
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest test/unit/media_test.rb -v`
Expected: FAIL — `uninitialized constant FlowChat::Media`

- [ ] **Step 3: Write the implementation**

Create `lib/flow_chat/media.rb`:

```ruby
require "net/http"
require "uri"

module FlowChat
  # Value object wrapping a single inbound media item parsed by a gateway.
  # Normalizes cross-platform differences (WhatsApp media-id, Telegram file_id,
  # Intercom/HTTP direct URL) behind #url and #download.
  class Media
    attr_reader :platform, :client

    def initialize(data, platform:, client: nil)
      @data = data
      @platform = platform
      @client = client
    end

    def type
      @data[:type]
    end

    def mime_type
      @data[:mime_type]
    end

    def caption
      @data[:caption]
    end

    def filename
      @data[:filename] || @data[:file_name]
    end

    def id
      @data[:id]
    end

    def file_id
      @data[:file_id]
    end

    def [](key)
      @data[key]
    end

    def to_h
      @data
    end

    # Resolve a fetchable URL for the media.
    def url
      case platform
      when :whatsapp then client.get_media_url(id)
      when :telegram then client.file_url(file_id)
      else @data[:url]
      end
    end

    # Fetch the raw bytes of the media.
    def download
      case platform
      when :whatsapp then client.download_media(id)
      when :telegram then client.download_file(file_id)
      else fetch(url)
      end
    end

    private

    def fetch(resource_url)
      return nil unless resource_url

      uri = URI(resource_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      response = http.get(uri.request_uri)
      response.body if response.is_a?(Net::HTTPSuccess)
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `ruby -Itest test/unit/media_test.rb -v`
Expected: PASS (all 5 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/flow_chat/media.rb test/unit/media_test.rb
git commit -m "feat: add FlowChat::Media inbound media value object"
```

```json:metadata
{"files": ["lib/flow_chat/media.rb", "test/unit/media_test.rb"], "verifyCommand": "ruby -Itest test/unit/media_test.rb -v", "acceptanceCriteria": ["metadata readers", "url/download dispatch per platform", "autoloads via Zeitwerk"], "requiresUserVerification": false}
```

---

### Task 2: Telegram client media download

**Goal:** Add `get_file`, `file_url`, and `download_file` to the Telegram client so inbound Telegram media can be fetched.

**Files:**
- Modify: `lib/flow_chat/telegram/client.rb` (add public methods before `private` at line 182)
- Test: `test/unit/telegram/client_test.rb`

**Acceptance Criteria:**
- [ ] `get_file(file_id)` calls the `getFile` API method with `{file_id:}`.
- [ ] `file_url(file_id)` returns `https://api.telegram.org/file/bot<bot_token>/<file_path>`, or `nil` if no `file_path`.
- [ ] `download_file(file_id)` GETs `file_url` and returns the body on success, `nil` otherwise.

**Verify:** `ruby -Itest test/unit/telegram/client_test.rb -v` → all pass

**Steps:**

- [ ] **Step 1: Write the failing test**

Add to `test/unit/telegram/client_test.rb` (match the file's existing setup — a `FlowChat::Telegram::Configuration` with `bot_token` and a `FlowChat::Telegram::Client`). Add:

```ruby
  def test_get_file_calls_getFile
    client = FlowChat::Telegram::Client.new(@config)
    client.stub(:api_request, {"ok" => true, "result" => {"file_path" => "photos/f.jpg"}}) do
      result = client.get_file("FID")
      assert_equal "photos/f.jpg", result.dig("result", "file_path")
    end
  end

  def test_file_url_builds_download_url
    client = FlowChat::Telegram::Client.new(@config)
    client.stub(:get_file, {"ok" => true, "result" => {"file_path" => "photos/f.jpg"}}) do
      assert_equal "https://api.telegram.org/file/bot#{@config.bot_token}/photos/f.jpg", client.file_url("FID")
    end
  end

  def test_file_url_returns_nil_without_file_path
    client = FlowChat::Telegram::Client.new(@config)
    client.stub(:get_file, {"ok" => false}) do
      assert_nil client.file_url("FID")
    end
  end
```

Note: if the existing test file defines `@config`/`@client` differently in `setup`, reuse that instead of re-instantiating.

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest test/unit/telegram/client_test.rb -v`
Expected: FAIL — `NoMethodError: undefined method 'get_file'`

- [ ] **Step 3: Write the implementation**

In `lib/flow_chat/telegram/client.rb`, immediately before the `private` keyword (line 182), add:

```ruby
      # Get file metadata (including file_path) for an inbound file_id
      def get_file(file_id)
        api_request("getFile", {file_id: file_id})
      end

      # Build the download URL for an inbound file_id
      def file_url(file_id)
        file_path = get_file(file_id).dig("result", "file_path")
        return nil unless file_path

        "https://api.telegram.org/file/bot#{@config.bot_token}/#{file_path}"
      end

      # Download the raw bytes for an inbound file_id
      def download_file(file_id)
        url = file_url(file_id)
        return nil unless url

        uri = URI(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        response = http.get(uri.request_uri)

        if response.is_a?(Net::HTTPSuccess)
          response.body
        else
          FlowChat.logger.error { "Telegram::Client: File download error: #{response.code}" }
          nil
        end
      end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `ruby -Itest test/unit/telegram/client_test.rb -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/flow_chat/telegram/client.rb test/unit/telegram/client_test.rb
git commit -m "feat: add Telegram client inbound file download (getFile)"
```

```json:metadata
{"files": ["lib/flow_chat/telegram/client.rb", "test/unit/telegram/client_test.rb"], "verifyCommand": "ruby -Itest test/unit/telegram/client_test.rb -v", "acceptanceCriteria": ["get_file", "file_url", "download_file"], "requiresUserVerification": false}
```

---

### Task 3: Wire `App` to expose inbound media, location, and contact

**Goal:** Replace the `nil` stubs in `App` so parsed inbound data reaches flows, normalizing single/array media into `media_items` with `media` as the first-item convenience.

**Files:**
- Modify: `lib/flow_chat/app.rb` (methods at lines 66-76; add private helper)
- Test: `test/integration/media_support_test.rb`

**Acceptance Criteria:**
- [ ] `media_items` returns `[]` when no media, one `FlowChat::Media` for a single hash, N for an array.
- [ ] `media` returns `media_items.first` (or `nil`).
- [ ] `location` returns `context["request.location"]`; `contact` returns `context["request.contact"]`; `contact_name` returns `context["request.user_name"]`.
- [ ] Each `FlowChat::Media` gets the right platform client from context.

**Verify:** `ruby -Itest test/integration/media_support_test.rb -v` → all pass

**Steps:**

- [ ] **Step 1: Write the failing test**

Add to `test/integration/media_support_test.rb`:

```ruby
  # ==========================================================================
  # INBOUND MEDIA EXPOSURE
  # ==========================================================================

  def test_whatsapp_inbound_media_exposed_via_app
    @whatsapp_context.input = FlowChat::Input::MEDIA
    @whatsapp_context["request.platform"] = :whatsapp
    @whatsapp_context["request.media"] = {type: :image, id: "MID", mime_type: "image/jpeg", caption: "hi"}
    app = FlowChat::App.new(@whatsapp_context)

    assert_instance_of FlowChat::Media, app.media
    assert_equal :image, app.media.type
    assert_equal "MID", app.media.id
    assert_equal 1, app.media_items.size
  end

  def test_intercom_inbound_multiple_media_exposed_via_app
    ctx = FlowChat::Context.new
    ctx.session = create_test_session_store
    ctx["request.platform"] = :intercom
    ctx["request.media"] = [
      {type: :image, url: "https://i/1.png", mime_type: "image/png"},
      {type: :document, url: "https://i/2.pdf", mime_type: "application/pdf"}
    ]
    app = FlowChat::App.new(ctx)

    assert_equal 2, app.media_items.size
    assert_equal "https://i/1.png", app.media.url
    assert_equal :document, app.media_items.last.type
  end

  def test_inbound_media_absent_returns_nil_and_empty
    @whatsapp_context.input = "just text"
    @whatsapp_context["request.platform"] = :whatsapp
    app = FlowChat::App.new(@whatsapp_context)

    assert_nil app.media
    assert_equal [], app.media_items
  end

  def test_location_and_contact_exposed_via_app
    @whatsapp_context["request.platform"] = :whatsapp
    @whatsapp_context["request.location"] = {latitude: 1.0, longitude: 2.0}
    @whatsapp_context["request.user_name"] = "John Doe"
    @whatsapp_context["request.contact"] = {name: "Jane", first_name: "Jane"}
    app = FlowChat::App.new(@whatsapp_context)

    assert_equal 1.0, app.location[:latitude]
    assert_equal "John Doe", app.contact_name
    assert_equal "Jane", app.contact[:name]
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest test/integration/media_support_test.rb -v`
Expected: FAIL — `app.media` is `nil` / `NoMethodError: undefined method 'media_items'`

- [ ] **Step 3: Write the implementation**

In `lib/flow_chat/app.rb`, replace the three stub methods (lines 66-76):

```ruby
    def contact_name
      context["request.user_name"]
    end

    def contact
      context["request.contact"]
    end

    def location
      context["request.location"]
    end

    def media
      media_items.first
    end

    def media_items
      raw = context["request.media"]
      return [] unless raw

      items = raw.is_a?(Array) ? raw : [raw]
      items.map { |data| FlowChat::Media.new(data, platform: platform, client: media_client) }
    end
```

Then add to the `protected`/`private` section (after `prepare_user_input`):

```ruby
    def media_client
      case platform
      when :whatsapp then context["whatsapp.client"]
      when :telegram then context["telegram.client"]
      when :intercom then context["intercom.client"]
      end
    end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `ruby -Itest test/integration/media_support_test.rb -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/flow_chat/app.rb test/integration/media_support_test.rb
git commit -m "feat: expose inbound media, location, and contact to flows"
```

```json:metadata
{"files": ["lib/flow_chat/app.rb", "test/integration/media_support_test.rb"], "verifyCommand": "ruby -Itest test/integration/media_support_test.rb -v", "acceptanceCriteria": ["media_items normalizes single/array/none", "media is first item", "location/contact/contact_name exposed", "correct platform client"], "requiresUserVerification": false}
```

---

### Task 4: Intercom gateway inbound media parsing

**Goal:** Parse Intercom message attachments (an array) into `context["request.media"]`, supporting multiple attachments per message.

**Files:**
- Modify: `lib/flow_chat/intercom/gateway/intercom_api.rb` (`extract_latest_user_message`, lines 266-299; and the caller that sets `context.input`, ~line 143-146)
- Test: `test/unit/intercom/gateway/intercom_api_test.rb`

**Acceptance Criteria:**
- [ ] Attachments on the initial message (`source`) and on reply parts are extracted into an array of media hashes.
- [ ] `content_type` maps to type: `image/*`→`:image`, `video/*`→`:video`, `audio/*`→`:audio`, else `:document`.
- [ ] When attachments exist, `context["request.media"]` is set and `context.input = FlowChat::Input::MEDIA`.
- [ ] Messages without attachments are unaffected (text still flows through unchanged).

**Verify:** `ruby -Itest test/unit/intercom/gateway/intercom_api_test.rb -v` → all pass

**Steps:**

- [ ] **Step 1: Write the failing test**

Add to `test/unit/intercom/gateway/intercom_api_test.rb` a test that drives the extraction. Match the file's existing style for building a gateway + webhook body. The core assertion:

```ruby
  def test_extract_maps_multiple_attachments_to_media_array
    gateway = build_gateway  # use existing helper/setup in this file
    conversation = {
      "source" => {
        "id" => "msg_1",
        "body" => "see attached",
        "attachments" => [
          {"name" => "a.png", "url" => "https://i/a.png", "content_type" => "image/png"},
          {"name" => "b.pdf", "url" => "https://i/b.pdf", "content_type" => "application/pdf"}
        ]
      }
    }
    result = gateway.send(:extract_latest_user_message, conversation, "conversation.user.created")
    assert_equal 2, result[:media].size
    assert_equal :image, result[:media][0][:type]
    assert_equal :document, result[:media][1][:type]
    assert_equal "https://i/a.png", result[:media][0][:url]
  end
```

Note: `extract_latest_user_message` returns a hash `{id:, body:}`. This task extends it to also include `media:` when attachments are present. If the existing test file lacks a `build_gateway` helper, instantiate the gateway the same way `setup` in that file does.

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest test/unit/intercom/gateway/intercom_api_test.rb -v`
Expected: FAIL — `result[:media]` is `nil`

- [ ] **Step 3: Write the implementation**

In `lib/flow_chat/intercom/gateway/intercom_api.rb`, add a private helper and use it in both branches of `extract_latest_user_message`. Add near the other private helpers:

```ruby
        def extract_attachments(raw)
          attachments = raw["attachments"] || []
          return nil if attachments.empty?

          attachments.map do |a|
            {
              type: intercom_media_type(a["content_type"]),
              url: a["url"],
              mime_type: a["content_type"],
              filename: a["name"]
            }
          end
        end

        def intercom_media_type(content_type)
          case content_type
          when %r{\Aimage/} then :image
          when %r{\Avideo/} then :video
          when %r{\Aaudio/} then :audio
          else :document
          end
        end
```

Update `extract_latest_user_message` to include media. In the `conversation.user.created` branch:

```ruby
          when "conversation.user.created"
            source = conversation["source"]
            if source && (source["body"] || source["attachments"]&.any?)
              {
                id: source["id"],
                body: source["body"],
                media: extract_attachments(source)
              }.compact
            end
```

In the `conversation.user.replied` branch, replace the returned hash:

```ruby
            if user_parts.any?
              latest_part = user_parts.last
              {
                id: latest_part["id"],
                body: latest_part["body"],
                media: extract_attachments(latest_part)
              }.compact
            end
```

Then, in the caller that sets `context.input` (around lines 143-146, where `latest_message` is used), set media and the sentinel input when present:

```ruby
              context["request.message_id"] = latest_message[:id]
              if latest_message[:media]
                context["request.media"] = latest_message[:media]
                context.input = FlowChat::Input::MEDIA
              else
                context.input = @client.parse_message(raw_body)
              end
```

Adjust to match the exact existing structure around line 143-150 (preserve the debug log line).

- [ ] **Step 4: Run test to verify it passes**

Run: `ruby -Itest test/unit/intercom/gateway/intercom_api_test.rb -v`
Expected: PASS

- [ ] **Step 5: Run the full Intercom + integration suites for regressions**

Run: `ruby -Itest test/unit/intercom/gateway/intercom_api_test.rb test/integration/intercom_integration_test.rb -v`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/flow_chat/intercom/gateway/intercom_api.rb test/unit/intercom/gateway/intercom_api_test.rb
git commit -m "feat: parse inbound Intercom attachments into request media"
```

```json:metadata
{"files": ["lib/flow_chat/intercom/gateway/intercom_api.rb", "test/unit/intercom/gateway/intercom_api_test.rb"], "verifyCommand": "ruby -Itest test/unit/intercom/gateway/intercom_api_test.rb -v", "acceptanceCriteria": ["attachments array parsed", "content_type mapping", "media sentinel input set", "text unaffected"], "requiresUserVerification": false}
```

---

### Task 5: HTTP gateway inbound media parsing

**Goal:** Let the HTTP gateway accept inbound media via request params so the simulator and API callers can submit media.

**Files:**
- Modify: `lib/flow_chat/http/gateway/simple.rb` (after `context.input` is set, ~line 47)
- Test: `test/unit/http/gateway/simple_test.rb`

**Acceptance Criteria:**
- [ ] When params include `media_url`, `context["request.media"]` is set to `{type:, url:, mime_type:}` (type from `media_type` param, default `:document`).
- [ ] When no text `input` is present but media is, `context.input = FlowChat::Input::MEDIA`.
- [ ] When text `input` is present, it still takes precedence (existing behavior preserved).
- [ ] Requests with neither are unaffected.

**Verify:** `ruby -Itest test/unit/http/gateway/simple_test.rb -v` → all pass

**Steps:**

- [ ] **Step 1: Write the failing test**

Add to `test/unit/http/gateway/simple_test.rb`, matching the file's existing controller/params mocking style. Core assertions:

```ruby
  def test_inbound_media_url_sets_request_media
    # Build controller whose request.params includes media_url (reuse this file's helper)
    controller = build_controller(params: {"media_url" => "https://x/a.jpg", "media_type" => "image", "mime_type" => "image/jpeg"})
    context = FlowChat::Context.new
    context.controller = controller
    gateway = FlowChat::Http::Gateway::Simple.new(->(_ctx) { [:text, "ok", nil, nil] }, {session_id: "s", user_id: "u"})
    gateway.call(context)

    assert_equal :image, context["request.media"][:type]
    assert_equal "https://x/a.jpg", context["request.media"][:url]
    assert_equal FlowChat::Input::MEDIA, context.input
  end

  def test_text_input_takes_precedence_over_media
    controller = build_controller(params: {"input" => "hello", "media_url" => "https://x/a.jpg"})
    context = FlowChat::Context.new
    context.controller = controller
    gateway = FlowChat::Http::Gateway::Simple.new(->(_ctx) { [:text, "ok", nil, nil] }, {session_id: "s", user_id: "u"})
    gateway.call(context)

    assert_equal "hello", context.input
  end
```

Note: reuse whatever controller/params builder the existing tests in this file use (e.g. a `mock_controller` helper). Do not invent a new mocking approach — mirror the file.

- [ ] **Step 2: Run test to verify it fails**

Run: `ruby -Itest test/unit/http/gateway/simple_test.rb -v`
Expected: FAIL — `context["request.media"]` is `nil`

- [ ] **Step 3: Write the implementation**

In `lib/flow_chat/http/gateway/simple.rb`, after the existing `context.input = params["input"].presence || ""` (line 47), add:

```ruby
          # Inbound media (optional): callers may submit a media URL
          if params["media_url"].present?
            context["request.media"] = {
              type: (params["media_type"].presence || "document").to_sym,
              url: params["media_url"],
              mime_type: params["mime_type"].presence
            }
            context.input = FlowChat::Input::MEDIA if context.input.blank?
          end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `ruby -Itest test/unit/http/gateway/simple_test.rb -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/flow_chat/http/gateway/simple.rb test/unit/http/gateway/simple_test.rb
git commit -m "feat: parse inbound media params in HTTP gateway"
```

```json:metadata
{"files": ["lib/flow_chat/http/gateway/simple.rb", "test/unit/http/gateway/simple_test.rb"], "verifyCommand": "ruby -Itest test/unit/http/gateway/simple_test.rb -v", "acceptanceCriteria": ["media_url sets request.media", "media sentinel when no text", "text precedence preserved"], "requiresUserVerification": false}
```

---

### Task 6: Full suite regression + docs

**Goal:** Confirm the whole test suite is green and note the new inbound media API in project docs.

**Files:**
- Modify: `README.md` or `docs/` (whichever documents flow APIs — add `app.media` / `app.media_items` / `app.location` / `app.contact` usage)

**Acceptance Criteria:**
- [ ] `rake test` passes with zero failures.
- [ ] Docs mention inbound media access (`app.media.download`, `media_items` for multi-attachment Intercom).

**Verify:** `bundle exec rake test` → 0 failures, 0 errors

**Steps:**

- [ ] **Step 1: Run the full suite**

Run: `bundle exec rake test`
Expected: 0 failures, 0 errors. Fix any regressions before proceeding.

- [ ] **Step 2: Add a short docs section**

Find where flow input APIs are documented (grep the README/docs for `app.msisdn` or `app.location`). Add a concise inbound-media example:

```ruby
photo = app.screen(:upload) { |p| p.ask "Send a photo" }
if app.media
  bytes = app.media.download          # raw file bytes
  url   = app.media.url               # fetchable URL
  app.media.type                      # :image, :document, ...
end
app.media_items                       # Array (Intercom may attach several)
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "docs: document inbound media access API"
```

```json:metadata
{"files": ["README.md"], "verifyCommand": "bundle exec rake test", "acceptanceCriteria": ["full suite green", "docs updated"], "requiresUserVerification": false}
```

---

## Self-Review Notes

- **Spec coverage:** Media object (Task 1), App wiring incl. media_items/location/contact (Task 3), Telegram download (Task 2), Intercom multi-attachment parsing (Task 4), HTTP parsing (Task 5), tests throughout, docs (Task 6). All spec sections mapped.
- **Type consistency:** `FlowChat::Media.new(data, platform:, client:)`, `media_items`, `media`, `client.file_url`/`download_file`/`get_media_url`/`download_media`, `intercom_media_type` used consistently across tasks.
- **Verification requirement scan:** Prompt "we need to add support for media" requires no user sign-off → NO. No verification task required.

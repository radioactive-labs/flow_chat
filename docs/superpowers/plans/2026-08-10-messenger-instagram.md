# Messenger and Instagram DM Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Facebook Messenger and Instagram DM gateways to FlowChat at parity with the WhatsApp gateway, on one shared Meta webhook implementation, and fix two WhatsApp bugs found while designing the choice ladder.

**Architecture:** `FlowChat::Meta::` holds what all three Meta platforms share: `X-Hub-Signature-256` validation, `hub.challenge` verification, and `MessagingGateway`, which implements the `entry[].messaging[]` envelope once. `Messenger::Gateway::SendApi` and `Instagram::Gateway::SendApi` each subclass `MessagingGateway` and override four hooks (platform symbol, configuration class, renderer class, account-id check). Choices render down a ladder (quick replies, carousel, numbered text) whose rung is decided by one shared helper so the renderer and the choice mapper cannot disagree.

**Tech Stack:** Ruby, Zeitwerk autoloading, Minitest, WebMock, Kramdown, ActiveSupport. Meta Graph API v23.0.

**User Verification:** YES. Two facts cannot be settled from this machine and need the user: (1) whether Instagram-via-Facebook-Login delivers webhooks under `object: "page"` or `object: "instagram"`, readable only from their Meta app dashboard, and (2) whether the Instagram carousel is legible for plain option menus on a real device. Task 20 is a dedicated verification checkpoint for both.

**Spec:** `docs/superpowers/specs/2026-08-10-messenger-instagram-design.md`

---

## Conventions for every task

- Run one test file with `ruby -Itest test/unit/path_test.rb`, one test with `ruby -Itest test/unit/path_test.rb -n test_name`, everything with `bundle exec rake test`.
- Never stage or commit anything beyond the files a task names.
- Logging uses block syntax: `FlowChat.logger.debug { "..." }`.
- No `respond_to?` guards. If a collaborator is required, call it.
- Docs prose: dense and plain, no marketing adjectives, **no em-dashes**.

## File Structure

### Created

| File | Responsibility |
|---|---|
| `lib/flow_chat/meta/signature_validation.rb` | `X-Hub-Signature-256` HMAC check, shared by 3 platforms |
| `lib/flow_chat/meta/webhook_verification.rb` | `hub.mode`/`hub.verify_token`/`hub.challenge` exchange |
| `lib/flow_chat/meta/choice_ladder.rb` | Decides which rung renders a given choice count |
| `lib/flow_chat/meta/messaging_gateway.rb` | The `entry[].messaging[]` envelope, dispatch, echoes, statuses, context |
| `lib/flow_chat/named_configuration.rb` | Named-configuration registry with per-class storage |
| `lib/flow_chat/id_generator.rb` | Moved from `whatsapp/id_generator.rb`, max length now configurable |
| `lib/flow_chat/messenger/configuration.rb` | Messenger credentials |
| `lib/flow_chat/messenger/client.rb` | Send API calls, text splitting, attachment upload |
| `lib/flow_chat/messenger/renderer.rb` | Messenger choice ladder and plain-text conversion |
| `lib/flow_chat/messenger/gateway/send_api.rb` | Messenger subclass of `MessagingGateway` |
| `lib/flow_chat/messenger/middleware/choice_mapper.rb` | Payload and position mapping back to choice keys |
| `lib/flow_chat/instagram/configuration.rb` | Instagram credentials |
| `lib/flow_chat/instagram/client.rb` | Instagram Send API calls, byte-based splitting |
| `lib/flow_chat/instagram/renderer.rb` | Instagram ladder, always numbers the body |
| `lib/flow_chat/instagram/gateway/send_api.rb` | Instagram subclass of `MessagingGateway` |
| `lib/flow_chat/instagram/middleware/choice_mapper.rb` | Instagram choice mapping |
| `docs/platforms/messenger.md`, `docs/platforms/instagram.md` | Platform guides |

### Modified

| File | Change |
|---|---|
| `lib/flow_chat/whatsapp/gateway/cloud_api.rb` | Uses shared `Meta::` modules; derives `echo_origin` |
| `lib/flow_chat/whatsapp/configuration.rb` | Uses `NamedConfiguration` |
| `lib/flow_chat/telegram/configuration.rb` | Uses `NamedConfiguration` |
| `lib/flow_chat/intercom/configuration.rb` | Uses `NamedConfiguration` |
| `lib/flow_chat/whatsapp/renderer.rb` | List capped at 10 rows; numbered fallback above |
| `lib/flow_chat/whatsapp/middleware/choice_mapper.rb` | Uses `FlowChat::IdGenerator`; stores position map |
| `lib/flow_chat/renderers/markdown_support.rb` | Adds `to_plain_text` |
| `lib/flow_chat/session/middleware.rb` | `:messenger` and `:instagram` default to `:user_id` |
| `lib/flow_chat/config.rb` | Adds `Config.messenger` and `Config.instagram` |
| `README.md`, `docs/gateway-context-variables.md` | Both platforms documented |

### Deleted

| File | Reason |
|---|---|
| `lib/flow_chat/whatsapp/id_generator.rb` | Moved to `lib/flow_chat/id_generator.rb` |

---

# Phase 1: Shared extractions and WhatsApp fixes

Phase 1 touches only existing code and is covered by existing suites. It lands before either new platform so that phases 2 and 3 build on proven shared code.

## Task 1: Extract Meta signature validation

**Goal:** One implementation of `X-Hub-Signature-256` validation, used by the WhatsApp gateway, with each platform keeping its own error class.

**Files:**
- Create: `lib/flow_chat/meta/signature_validation.rb`
- Modify: `lib/flow_chat/whatsapp/gateway/cloud_api.rb` (remove `valid_webhook_signature?`, lines 325-377)
- Test: `test/unit/whatsapp/gateway/cloud_api_test.rb` (existing, must stay green)

**Acceptance Criteria:**
- [ ] `FlowChat::Meta::SignatureValidation` provides `valid_webhook_signature?(request)`
- [ ] `skip_signature_validation` short-circuits to `true`
- [ ] A blank `app_secret` raises the *including gateway's* error class, not a shared one
- [ ] A missing `X-Hub-Signature-256` header returns `false`
- [ ] WhatsApp's three `assert_raises(FlowChat::Whatsapp::ConfigurationError)` tests still pass

**Verify:** `ruby -Itest test/unit/whatsapp/gateway/cloud_api_test.rb` → all pass, 0 failures

**Steps:**

- [ ] **Step 1: Confirm the existing tests pass before touching anything**

Run: `ruby -Itest test/unit/whatsapp/gateway/cloud_api_test.rb`
Expected: PASS. Record the assertion count so you can compare after.

- [ ] **Step 2: Create the shared module**

Create `lib/flow_chat/meta/signature_validation.rb`:

```ruby
require "openssl"

module FlowChat
  module Meta
    # Raised when a Meta gateway cannot validate a signature because it was not
    # configured to. Platforms override configuration_error_class to raise their own.
    class ConfigurationError < StandardError; end

    # X-Hub-Signature-256 validation, shared by every Meta webhook gateway.
    #
    # The including gateway must have @config responding to #app_secret and
    # #skip_signature_validation. It may override platform_label, log_tag and
    # configuration_error_class.
    module SignatureValidation
      def valid_webhook_signature?(request)
        if @config.skip_signature_validation
          FlowChat.logger.debug { "#{log_tag}: Webhook signature validation is disabled" }
          return true
        end

        if @config.app_secret.blank?
          error_msg = "#{platform_label} app_secret is required for webhook signature validation. " \
            "Either configure app_secret or set skip_signature_validation=true to explicitly disable validation."
          FlowChat.logger.error { "#{log_tag}: #{error_msg}" }
          raise configuration_error_class, error_msg
        end

        signature_header = request.headers["X-Hub-Signature-256"]
        unless signature_header
          FlowChat.logger.warn { "#{log_tag}: No X-Hub-Signature-256 header found in request" }
          return false
        end

        expected_signature = signature_header.sub("sha256=", "")

        request.body.rewind
        body = request.body.read
        request.body.rewind

        calculated_signature = OpenSSL::HMAC.hexdigest(
          OpenSSL::Digest.new("sha256"),
          @config.app_secret,
          body
        )

        signature_valid = FlowChat::Security.secure_compare(expected_signature, calculated_signature)

        if signature_valid
          FlowChat.logger.debug { "#{log_tag}: Webhook signature validation successful" }
        else
          FlowChat.logger.warn { "#{log_tag}: Webhook signature validation failed - signatures do not match" }
        end

        signature_valid
      rescue => e
        # A misconfiguration is the developer's problem and must not be swallowed
        # into a plain "invalid signature".
        raise if e.is_a?(configuration_error_class)

        FlowChat.logger.error { "#{log_tag}: Error validating webhook signature: #{e.class.name}: #{e.message}" }
        false
      end

      private

      def configuration_error_class
        FlowChat::Meta::ConfigurationError
      end

      def platform_label
        "Meta"
      end

      def log_tag
        self.class.name.split("::").last
      end
    end
  end
end
```

- [ ] **Step 3: Point the WhatsApp gateway at it**

In `lib/flow_chat/whatsapp/gateway/cloud_api.rb`, add the include next to the existing ones:

```ruby
        include FlowChat::Instrumentation
        include FlowChat::GatewayAsyncSupport
        include FlowChat::Meta::SignatureValidation
```

Delete the entire private `valid_webhook_signature?` method (lines 325-377) and add the three hook overrides in the private section:

```ruby
        def configuration_error_class
          FlowChat::Whatsapp::ConfigurationError
        end

        def platform_label
          "WhatsApp"
        end

        def log_tag
          "CloudApi"
        end
```

- [ ] **Step 4: Run the WhatsApp gateway tests**

Run: `ruby -Itest test/unit/whatsapp/gateway/cloud_api_test.rb`
Expected: PASS, same assertion count as Step 1. The three `ConfigurationError` tests confirm the hook works.

- [ ] **Step 5: Run the full suite**

Run: `bundle exec rake test`
Expected: PASS, 0 failures, 0 errors.

- [ ] **Step 6: Commit**

```bash
git add lib/flow_chat/meta/signature_validation.rb lib/flow_chat/whatsapp/gateway/cloud_api.rb
git commit -m "refactor(meta): share the webhook signature check between platforms"
```

---

## Task 2: Extract Meta webhook verification

**Goal:** One implementation of the `hub.challenge` exchange, including the guard that a gateway with no verify token verifies nothing.

**Files:**
- Create: `lib/flow_chat/meta/webhook_verification.rb`
- Modify: `lib/flow_chat/whatsapp/gateway/cloud_api.rb` (remove `handle_verification`, lines 79-110)
- Test: `test/unit/whatsapp/gateway/cloud_api_test.rb` (existing)

**Acceptance Criteria:**
- [ ] `FlowChat::Meta::WebhookVerification#handle_verification` renders the challenge on a token match
- [ ] A blank configured verify token returns `:forbidden` even when the request also sends a blank token
- [ ] `WEBHOOK_VERIFIED` and `WEBHOOK_FAILED` carry the including gateway's `platform`

**Verify:** `ruby -Itest test/unit/whatsapp/gateway/cloud_api_test.rb -n test_get_request_webhook_verification` → PASS

**Steps:**

- [ ] **Step 1: Create the module**

Create `lib/flow_chat/meta/webhook_verification.rb`:

```ruby
module FlowChat
  module Meta
    # The GET handshake Meta performs when a webhook URL is registered.
    #
    # The including gateway must have @config responding to #verify_token,
    # @controller, and must define #platform.
    module WebhookVerification
      def handle_verification(context)
        params = @controller.request.params

        verify_token = @config.verify_token
        provided_token = params["hub.verify_token"]
        challenge = params["hub.challenge"]

        # A configuration with no verify token must not verify anything. Without
        # the presence check a missing token on both sides compares equal, and
        # anyone could claim the endpoint by asking for the challenge.
        verified = verify_token.present? && FlowChat::Security.secure_compare(provided_token.to_s, verify_token)

        FlowChat.logger.debug { "#{log_tag}: Webhook verification - provided token matches: #{verified}" }

        if verified
          instrument(Events::WEBHOOK_VERIFIED, {
            challenge: challenge,
            platform: platform
          })

          @controller.render plain: challenge
        else
          instrument(Events::WEBHOOK_FAILED, {
            reason: "Invalid verify token",
            platform: platform
          })

          @controller.head :forbidden
        end
      end
    end
  end
end
```

- [ ] **Step 2: Point the WhatsApp gateway at it**

Add the include:

```ruby
        include FlowChat::Meta::WebhookVerification
```

Delete the private `handle_verification` method (lines 79-110) and add `platform` to the private section:

```ruby
        def platform
          :whatsapp
        end
```

- [ ] **Step 3: Run the verification tests**

Run: `ruby -Itest test/unit/whatsapp/gateway/cloud_api_test.rb -n /verification|verify_token/`
Expected: PASS.

- [ ] **Step 4: Run the full suite**

Run: `bundle exec rake test`
Expected: PASS, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/flow_chat/meta/webhook_verification.rb lib/flow_chat/whatsapp/gateway/cloud_api.rb
git commit -m "refactor(meta): share the webhook verification handshake"
```

---

## Task 3: Extract the named-configuration registry

**Goal:** One registry implementation with per-class storage, replacing three verbatim copies.

**Files:**
- Create: `lib/flow_chat/named_configuration.rb`
- Create: `test/unit/named_configuration_test.rb`
- Modify: `lib/flow_chat/whatsapp/configuration.rb:46-105`, `lib/flow_chat/telegram/configuration.rb:46-85`, `lib/flow_chat/intercom/configuration.rb:53-95`

**Acceptance Criteria:**
- [ ] `register`, `get`, `exists?`, `configuration_names`, `clear_all!`, `register_as` all provided by the module
- [ ] Storage is **per including class**: registering `:default` on Messenger does not make `Whatsapp::Configuration.exists?(:default)` true
- [ ] `get` on a missing name raises `ArgumentError` with each platform's existing message text preserved: `"WhatsApp configuration 'x' not found"`, `"Telegram configuration 'x' not found"`, `"Intercom configuration 'x' not found"`

**Verify:** `ruby -Itest test/unit/named_configuration_test.rb && ruby -Itest test/unit/telegram/configuration_test.rb && ruby -Itest test/unit/intercom/configuration_test.rb` → all pass

**Steps:**

- [ ] **Step 1: Write the failing test, isolation first**

Create `test/unit/named_configuration_test.rb`:

```ruby
require "test_helper"

class NamedConfigurationTest < Minitest::Test
  def setup
    FlowChat::Whatsapp::Configuration.clear_all!
    FlowChat::Telegram::Configuration.clear_all!
  end

  def teardown
    FlowChat::Whatsapp::Configuration.clear_all!
    FlowChat::Telegram::Configuration.clear_all!
  end

  # The bug a shared @@configurations would have introduced: one merged registry
  # across every platform.
  def test_registries_are_per_class
    FlowChat::Whatsapp::Configuration.new(:shared_name)

    assert FlowChat::Whatsapp::Configuration.exists?(:shared_name)
    refute FlowChat::Telegram::Configuration.exists?(:shared_name)
  end

  def test_get_returns_the_registered_configuration
    config = FlowChat::Whatsapp::Configuration.new(:acme)

    assert_same config, FlowChat::Whatsapp::Configuration.get(:acme)
  end

  def test_get_raises_with_the_platform_label
    error = assert_raises(ArgumentError) { FlowChat::Whatsapp::Configuration.get(:missing) }
    assert_equal "WhatsApp configuration 'missing' not found", error.message

    error = assert_raises(ArgumentError) { FlowChat::Telegram::Configuration.get(:missing) }
    assert_equal "Telegram configuration 'missing' not found", error.message
  end

  def test_configuration_names_lists_only_that_platform
    FlowChat::Whatsapp::Configuration.new(:wa_one)
    FlowChat::Telegram::Configuration.new(:tg_one)

    assert_equal [:wa_one], FlowChat::Whatsapp::Configuration.configuration_names
    assert_equal [:tg_one], FlowChat::Telegram::Configuration.configuration_names
  end
end
```

- [ ] **Step 2: Run it and watch it fail**

Run: `ruby -Itest test/unit/named_configuration_test.rb`
Expected: FAIL. The per-class test may pass by accident today (each class has its own `@@configurations`), but `test_get_raises_with_the_platform_label` and the others should run green only once the module exists and is wired. Confirm the file at least loads.

- [ ] **Step 3: Write the module**

Create `lib/flow_chat/named_configuration.rb`:

```ruby
module FlowChat
  # The named-configuration registry every platform's Configuration shares.
  #
  # Storage is a class-level ivar on the including class, not a class variable.
  # A @@configurations in a shared module would give every platform one merged
  # registry, so a name registered for Messenger would resolve for WhatsApp.
  module NamedConfiguration
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def configurations
        @configurations ||= {}
      end

      def register(name, config)
        FlowChat.logger.debug { "#{self.name}: Registering configuration '#{name}'" }
        configurations[name.to_sym] = config
      end

      def get(name)
        config = configurations[name.to_sym]
        unless config
          FlowChat.logger.error { "#{self.name}: Configuration '#{name}' not found" }
          raise ArgumentError, "#{configuration_label} configuration '#{name}' not found"
        end

        FlowChat.logger.debug { "#{self.name}: Retrieved configuration '#{name}'" }
        config
      end

      def exists?(name)
        configurations.key?(name.to_sym)
      end

      def configuration_names
        configurations.keys
      end

      def clear_all!
        FlowChat.logger.debug { "#{self.name}: Clearing all registered configurations" }
        configurations.clear
      end

      # The platform's name as it appears in the not-found message. Overridden
      # where the constant name and the product name differ, as with WhatsApp.
      def configuration_label
        name.split("::")[-2]
      end
    end

    def register_as(name)
      FlowChat.logger.debug { "#{self.class.name}: Registering configuration as '#{name}'" }
      @name = name.to_sym
      self.class.register(@name, self)
      self
    end
  end
end
```

- [ ] **Step 4: Wire the three existing classes**

In `lib/flow_chat/whatsapp/configuration.rb`, delete `@@configurations = {}` and the methods `self.register`, `self.get`, `self.exists?`, `self.configuration_names`, `self.clear_all!` and `register_as` (lines 46-105 region). Add near the top of the class body:

```ruby
      include FlowChat::NamedConfiguration

      # "Whatsapp" is the constant, "WhatsApp" is the product.
      def self.configuration_label
        "WhatsApp"
      end
```

Do the same in `lib/flow_chat/telegram/configuration.rb` and `lib/flow_chat/intercom/configuration.rb`, but without the `configuration_label` override: `name.split("::")[-2]` already yields `"Telegram"` and `"Intercom"`.

- [ ] **Step 5: Run the tests**

Run: `ruby -Itest test/unit/named_configuration_test.rb`
Expected: PASS, 4 tests.

Run: `ruby -Itest test/unit/telegram/configuration_test.rb && ruby -Itest test/unit/intercom/configuration_test.rb`
Expected: PASS. These are the regression net for the two migrations that have direct coverage.

- [ ] **Step 6: Run the full suite**

Run: `bundle exec rake test`
Expected: PASS, 0 failures. WhatsApp's configuration has no direct test, so its migration rides on the gateway and client suites.

- [ ] **Step 7: Commit**

```bash
git add lib/flow_chat/named_configuration.rb test/unit/named_configuration_test.rb \
        lib/flow_chat/whatsapp/configuration.rb lib/flow_chat/telegram/configuration.rb \
        lib/flow_chat/intercom/configuration.rb
git commit -m "refactor(config): keep the named configuration registry in one place"
```

---

## Task 4: Move IdGenerator up and make its cap configurable

**Goal:** `FlowChat::IdGenerator` usable by any platform, with the maximum length passed in rather than fixed at WhatsApp's 256.

**Files:**
- Create: `lib/flow_chat/id_generator.rb`
- Delete: `lib/flow_chat/whatsapp/id_generator.rb`
- Modify: `lib/flow_chat/whatsapp/middleware/choice_mapper.rb:1` (the `require_relative`) and its `IdGenerator.new` call
- Move: `test/unit/whatsapp/id_generator_test.rb` to `test/unit/id_generator_test.rb`

**Acceptance Criteria:**
- [ ] `FlowChat::IdGenerator.new(max_length: 1000)` truncates at 1000
- [ ] `FlowChat::IdGenerator.new` still defaults to 256, so WhatsApp behavior is unchanged
- [ ] Duplicate labels still get a hash suffix, and the suffix still fits inside the cap
- [ ] `FlowChat::Whatsapp::IdGenerator` no longer exists

**Verify:** `ruby -Itest test/unit/id_generator_test.rb` → PASS

**Steps:**

- [ ] **Step 1: Move the file and the test**

```bash
git mv lib/flow_chat/whatsapp/id_generator.rb lib/flow_chat/id_generator.rb
git mv test/unit/whatsapp/id_generator_test.rb test/unit/id_generator_test.rb
```

- [ ] **Step 2: Reopen the class one level up and parameterize the cap**

In `lib/flow_chat/id_generator.rb`, change the module nesting from `FlowChat::Whatsapp::IdGenerator` to `FlowChat::IdGenerator`, replace the `MAX_ID_LENGTH` constant usage with an instance attribute, and keep `HASH_SUFFIX_LENGTH`:

```ruby
require "digest"

module FlowChat
  # Generates platform-safe ids from choice labels.
  #
  # Interactive replies are identified by an id rather than by the label the user
  # saw, and every platform caps that id: WhatsApp list rows at 256 characters,
  # Messenger quick-reply payloads at 1000. The cap is a constructor argument so
  # one generator serves all of them.
  class IdGenerator
    DEFAULT_MAX_ID_LENGTH = 256
    HASH_SUFFIX_LENGTH = 3

    attr_reader :max_length

    def initialize(max_length: DEFAULT_MAX_ID_LENGTH)
      @max_length = max_length
      @generated_ids = []
    end

    # ... generate_id, reset, generated_ids unchanged ...

    private

    # ... normalize_label unchanged ...

    def add_hash_suffix(base_id, original_label)
      hash_input = "#{original_label}_#{@generated_ids.count { |id| id.start_with?(base_id) }}"
      hash = Digest::SHA256.hexdigest(hash_input)[0...HASH_SUFFIX_LENGTH]

      max_base_length = max_length - HASH_SUFFIX_LENGTH - 1
      truncated_base = base_id[0...max_base_length]

      "#{truncated_base} #{hash}"
    end

    def truncate_to_limit(id)
      return id if id.length <= max_length
      id[0...max_length]
    end
  end
end
```

- [ ] **Step 3: Update the test file's class references**

In `test/unit/id_generator_test.rb`, replace every `FlowChat::Whatsapp::IdGenerator` with `FlowChat::IdGenerator`, and add a test for the new cap:

```ruby
  def test_max_length_is_configurable
    generator = FlowChat::IdGenerator.new(max_length: 10)

    assert_equal 10, generator.generate_id("a" * 50).length
  end

  def test_default_max_length_is_unchanged
    generator = FlowChat::IdGenerator.new

    assert_equal 256, generator.generate_id("a" * 300).length
  end
```

- [ ] **Step 4: Update the WhatsApp choice mapper**

In `lib/flow_chat/whatsapp/middleware/choice_mapper.rb`, delete line 1 (`require_relative "../id_generator"`) since Zeitwerk resolves `FlowChat::IdGenerator`, and change the instantiation inside `create_id_mapping`:

```ruby
          id_generator = FlowChat::IdGenerator.new
```

- [ ] **Step 5: Run the tests**

Run: `ruby -Itest test/unit/id_generator_test.rb`
Expected: PASS.

Run: `ruby -Itest test/unit/whatsapp/middleware/choice_mapper_test.rb`
Expected: PASS.

- [ ] **Step 6: Run the full suite**

Run: `bundle exec rake test`
Expected: PASS, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add -A lib/flow_chat/id_generator.rb lib/flow_chat/whatsapp/ test/unit/id_generator_test.rb
git commit -m "refactor(choices): lift the id generator out of whatsapp"
```

---

## Task 5: Add plain-text markdown conversion

**Goal:** `to_plain_text` on `Renderers::MarkdownSupport`, for the two platforms that support no rich text at all.

**Files:**
- Modify: `lib/flow_chat/renderers/markdown_support.rb`
- Create: `test/unit/renderers/plain_text_support_test.rb`

**Acceptance Criteria:**
- [ ] Emphasis markers are removed, leaving the words: `**bold**` becomes `bold`
- [ ] `ul` renders as `• item` lines, `ol` as `1. item` lines
- [ ] A link renders as `text (url)`, and as bare `url` when the text equals the url
- [ ] HTML entities are decoded, and runs of 3 or more newlines collapse to 2

**Verify:** `ruby -Itest test/unit/renderers/plain_text_support_test.rb` → PASS

**Steps:**

- [ ] **Step 1: Write the failing test**

Create `test/unit/renderers/plain_text_support_test.rb`:

```ruby
require "test_helper"

class PlainTextSupportTest < Minitest::Test
  class Subject
    include FlowChat::Renderers::MarkdownSupport
    public :to_plain_text
  end

  def setup
    @subject = Subject.new
  end

  def test_strips_emphasis
    assert_equal "bold and italic", @subject.to_plain_text("**bold** and _italic_")
  end

  def test_unordered_list_becomes_bullets
    assert_equal "• one\n• two", @subject.to_plain_text("- one\n- two")
  end

  def test_ordered_list_is_numbered
    assert_equal "1. one\n2. two", @subject.to_plain_text("1. one\n2. two")
  end

  def test_link_shows_text_and_url
    assert_equal "Docs (https://example.com)", @subject.to_plain_text("[Docs](https://example.com)")
  end

  def test_link_with_url_as_text_shows_url_once
    assert_equal "https://example.com", @subject.to_plain_text("[https://example.com](https://example.com)")
  end

  def test_decodes_entities
    assert_equal "Tom & Jerry", @subject.to_plain_text("Tom &amp; Jerry")
  end

  def test_nil_is_empty_string
    assert_equal "", @subject.to_plain_text(nil)
  end
end
```

- [ ] **Step 2: Run it and watch it fail**

Run: `ruby -Itest test/unit/renderers/plain_text_support_test.rb`
Expected: FAIL with `NoMethodError: undefined method 'to_plain_text'`.

- [ ] **Step 3: Implement it**

Add to `lib/flow_chat/renderers/markdown_support.rb`, inside the module and above `private`:

```ruby
      # Markdown rendered as plain text, for platforms with no rich text at all.
      # Messenger and Instagram both fall here: they display exactly the
      # characters sent, so any leftover markup is noise the user reads.
      def to_plain_text(text)
        return "" if text.nil?

        html = Kramdown::Document.new(text.to_s, **kramdown_options).to_html.strip
        html_to_plain_text(html)
      end
```

And in the private section:

```ruby
      def html_to_plain_text(html)
        result = html.dup

        # Code blocks and inline code keep their content, lose their markers.
        result.gsub!(%r{<pre[^>]*><code[^>]*>(.*?)</code></pre>}m) { $1.strip }
        result.gsub!(%r{<code[^>]*>(.*?)</code>}m) { $1 }

        # Links first: the anchor text is needed before tags are stripped.
        result.gsub!(%r{<a[^>]*href=["']([^"']+)["'][^>]*>(.*?)</a>}m) do
          url, text = $1, $2
          (text == url) ? url : "#{text} (#{url})"
        end

        result.gsub!(%r{<ul[^>]*>(.*?)</ul>}m) do
          $1.scan(%r{<li[^>]*>(.*?)</li>}m).flatten.map { |item| "• #{item.strip}" }.join("\n")
        end
        result.gsub!(%r{<ol[^>]*>(.*?)</ol>}m) do
          $1.scan(%r{<li[^>]*>(.*?)</li>}m).flatten.map.with_index(1) { |item, i| "#{i}. #{item.strip}" }.join("\n")
        end

        result.gsub!(%r{<blockquote[^>]*>(.*?)</blockquote>}m) do
          $1.lines.map { |line| "> #{line.strip}" }.join("\n")
        end

        result.gsub!(%r{<p[^>]*>(.*?)</p>}m) { "#{$1}\n\n" }
        result.gsub!(/<br\s*\/?>/, "\n")

        # Every remaining tag, emphasis included, goes without replacement.
        result.gsub!(/<[^>]+>/, "")

        result.gsub!("&amp;", "&")
        result.gsub!("&lt;", "<")
        result.gsub!("&gt;", ">")
        result.gsub!("&quot;", '"')
        result.gsub!("&#39;", "'")
        result.gsub!("&nbsp;", " ")

        result.gsub!(/\n{3,}/, "\n\n")

        result.strip
      end
```

- [ ] **Step 4: Run the test**

Run: `ruby -Itest test/unit/renderers/plain_text_support_test.rb`
Expected: PASS, 7 tests.

- [ ] **Step 5: Confirm nothing else regressed**

Run: `bundle exec rake test`
Expected: PASS. `to_html` and `to_whatsapp` are untouched.

- [ ] **Step 6: Commit**

```bash
git add lib/flow_chat/renderers/markdown_support.rb test/unit/renderers/plain_text_support_test.rb
git commit -m "feat(renderers): render markdown as plain text"
```

---

## Task 6: Fix WhatsApp lists above 10 choices

**Goal:** Stop building list payloads Meta rejects. Meta allows 10 rows for all sections combined, so above 10 choices the renderer falls back to a numbered body.

**Files:**
- Modify: `lib/flow_chat/whatsapp/renderer.rb:186-217` (`build_list_message`, `build_interactive_message`)
- Modify: `test/unit/whatsapp/renderer_test.rb:200-235` (the section-slicing assertions)
- Modify: `lib/flow_chat/whatsapp/middleware/choice_mapper.rb` (store a position map for the numbered rung)

**Acceptance Criteria:**
- [ ] 3 or fewer choices render `:interactive_buttons`, unchanged
- [ ] 4 to 10 choices render `:interactive_list` with exactly one section
- [ ] 11 or more choices render `:text` with each option numbered in the body, and no `sections` key
- [ ] No rendered list ever contains more than 10 rows in total
- [ ] Typing `"3"` on a numbered screen resolves to the third choice's original key

**Verify:** `ruby -Itest test/unit/whatsapp/renderer_test.rb && ruby -Itest test/unit/whatsapp/middleware/choice_mapper_test.rb` → PASS

**Steps:**

- [ ] **Step 1: Write the failing tests**

Replace the existing `test_list_message_pagination_for_many_choices` (around `test/unit/whatsapp/renderer_test.rb:200-214`) with:

```ruby
  # Meta allows "up to 10 sections, with up to 10 rows for all sections combined",
  # so the old three-sections-of-ten payload was rejected on send.
  def test_list_is_capped_at_ten_rows
    choices = (1..10).to_h { |i| ["key#{i}", "Option #{i}"] }

    result = FlowChat::Whatsapp::Renderer.new("Pick one", choices: choices).render

    assert_equal :interactive_list, result[0]
    assert_equal 1, result[2][:sections].length
    assert_equal 10, result[2][:sections][0][:rows].length
  end

  def test_more_than_ten_choices_fall_back_to_a_numbered_body
    choices = (1..25).to_h { |i| ["key#{i}", "Option #{i}"] }

    result = FlowChat::Whatsapp::Renderer.new("Pick one", choices: choices).render

    assert_equal :text, result[0]
    assert_nil result[2][:sections]
    assert_includes result[1], "1. Option 1"
    assert_includes result[1], "25. Option 25"
    assert_includes result[1], "Pick one"
  end

  def test_three_or_fewer_choices_still_use_buttons
    choices = {"a" => "Alpha", "b" => "Beta"}

    result = FlowChat::Whatsapp::Renderer.new("Pick one", choices: choices).render

    assert_equal :interactive_buttons, result[0]
  end
```

- [ ] **Step 2: Run and watch them fail**

Run: `ruby -Itest test/unit/whatsapp/renderer_test.rb -n test_more_than_ten_choices_fall_back_to_a_numbered_body`
Expected: FAIL. It returns `:interactive_list` with 3 sections.

- [ ] **Step 3: Fix the renderer**

In `lib/flow_chat/whatsapp/renderer.rb`, add the cap constant to the class body:

```ruby
      # Meta: "up to 10 sections, with up to 10 rows for all sections combined".
      MAX_LIST_ROWS = 10
      MAX_BUTTONS = 3
```

Change `build_interactive_message` to a three-way ladder:

```ruby
      def build_interactive_message(choice_hash)
        if choice_hash.length <= MAX_BUTTONS
          build_buttons_message(choice_hash)
        elsif choice_hash.length <= MAX_LIST_ROWS
          build_list_message(choice_hash)
        else
          build_numbered_message(choice_hash)
        end
      end
```

Replace the section-slicing branch in `build_list_message` with a single section, and add the fallback:

```ruby
      def build_list_message(choices)
        items = choices.map do |key, value|
          original_text = value.to_s
          truncated_title = truncate_text(original_text, 24)

          description = if original_text.length > 24
            truncate_text(original_text, 72)
          end

          {
            id: key.to_s,
            title: truncated_title,
            description: description
          }.compact
        end

        [:interactive_list, formatted_message, {sections: [{title: "Options", rows: items}]}]
      end

      # Above the row cap there is no interactive surface left, so the options go
      # in the body and the user types a number. The choice mapper stores the
      # positions for this rung so the digit resolves to the original key.
      def build_numbered_message(choices)
        numbered = choices.values.map.with_index(1) { |label, i| "#{i}. #{label}" }.join("\n")

        [:text, "#{formatted_message}\n\n#{numbered}", {}]
      end
```

- [ ] **Step 4: Run the renderer tests**

Run: `ruby -Itest test/unit/whatsapp/renderer_test.rb`
Expected: PASS. If any other test asserted multi-section output, update it to the new ladder rather than restoring the old behavior.

- [ ] **Step 5: Teach the choice mapper the numbered rung**

In `lib/flow_chat/whatsapp/middleware/choice_mapper.rb`, store a position map alongside the id map whenever the numbered rung will be used, and resolve ids before positions. Replace `create_id_mapping` and add the resolution fallback:

```ruby
        def create_id_mapping(choices)
          id_generator = FlowChat::IdGenerator.new
          id_choices = {}
          choice_mapping = {}

          choices.each do |key, value|
            generated_id = id_generator.generate_id(value.to_s)
            id_choices[generated_id] = value
            choice_mapping[generated_id] = key.to_s
          end

          store_choice_mapping(choice_mapping)

          # Above the row cap the renderer numbers the options in the body, so
          # the reply is a digit rather than a row id.
          if choices.length > FlowChat::Whatsapp::Renderer::MAX_LIST_ROWS
            store_position_mapping(choices.keys.map.with_index(1) { |key, i| [i.to_s, key.to_s] }.to_h)
          else
            clear_position_mapping
          end

          id_choices
        end

        def store_position_mapping(mapping)
          @session.set("whatsapp.position_mapping", mapping)
        end

        def get_position_mapping
          @session.get("whatsapp.position_mapping") || {}
        end

        def clear_position_mapping
          @session.delete("whatsapp.position_mapping")
        end
```

Then widen `intercept?` and `handle_choice_input` to consult both maps, ids first:

```ruby
        def resolved_choice
          input = @context.input.to_s
          get_choice_mapping[input] || get_position_mapping[input]
        end

        def intercept?
          @context.input.present? && resolved_choice.present?
        end

        def handle_choice_input
          original_choice = resolved_choice
          FlowChat.logger.info { "Whatsapp::ChoiceMapper: Resolving choice input #{@context.input} to #{original_choice}" }
          @context.input = original_choice
        end
```

Ids are resolved before positions because the two key spaces can overlap: `IdGenerator#normalize_label` keeps `\w`, which includes digits, so a choice labelled `"1"` generates the id `"1"`.

- [ ] **Step 6: Test the numbered resolution**

Add to `test/unit/whatsapp/middleware/choice_mapper_test.rb`:

```ruby
  def test_typed_number_resolves_on_the_numbered_rung
    choices = (1..25).to_h { |i| ["key#{i}", "Option #{i}"] }
    app = ->(context) { [:prompt, "Pick one", choices, nil] }
    mapper = FlowChat::Whatsapp::Middleware::ChoiceMapper.new(app)

    context = build_choice_mapper_context(input: "")
    mapper.call(context)

    second_turn = build_choice_mapper_context(input: "3", session: context.session)
    mapper.call(second_turn)

    assert_equal "key3", second_turn.input
  end
```

Match the existing helper names in that file. If it builds contexts inline rather than through a helper, follow its established style instead of introducing `build_choice_mapper_context`.

Run: `ruby -Itest test/unit/whatsapp/middleware/choice_mapper_test.rb`
Expected: PASS.

- [ ] **Step 7: Run the full suite**

Run: `bundle exec rake test`
Expected: PASS, 0 failures.

- [ ] **Step 8: Commit**

```bash
git add lib/flow_chat/whatsapp/renderer.rb lib/flow_chat/whatsapp/middleware/choice_mapper.rb \
        test/unit/whatsapp/renderer_test.rb test/unit/whatsapp/middleware/choice_mapper_test.rb
git commit -m "fix(whatsapp): stop building list payloads Meta rejects

Meta allows ten rows for all sections combined, not ten per section, so
slicing twenty-five choices into three sections produced a payload that
failed on send. The section titles read like pagination but nothing was
paged: no second message, no stored offset.

Above ten choices the options now go in the body numbered, and the choice
mapper stores their positions so a typed digit resolves. Ids are resolved
before positions because a choice labelled \"1\" generates the id \"1\"."
```

---

## Task 7: Say who sent a WhatsApp echo

**Goal:** Coexistence echoes report whether our app, another app, or a human in the business inbox sent the message.

**Files:**
- Modify: `lib/flow_chat/whatsapp/gateway/cloud_api.rb:309-323` (`handle_unmodelled_field`)
- Modify: `test/unit/whatsapp/gateway/cloud_api_test.rb`

**Acceptance Criteria:**
- [ ] `WEBHOOK_RECEIVED` for an echo field carries `echo_origin`
- [ ] `echo_origin` is `:self` when the payload's `app_id` equals the configured `app_id`
- [ ] `echo_origin` is `:other_app` when an `app_id` is present but different
- [ ] `echo_origin` is `:human_agent` when no `app_id` is present
- [ ] Non-echo fields are published exactly as before, with no `echo_origin` key

**Verify:** `ruby -Itest test/unit/whatsapp/gateway/cloud_api_test.rb -n /echo/` → PASS

**Steps:**

- [ ] **Step 1: Write the failing tests**

Add to `test/unit/whatsapp/gateway/cloud_api_test.rb`:

```ruby
  def test_echo_from_a_human_in_the_business_inbox
    @mock_config.app_id = "our_app"
    events = capture_events(FlowChat::Instrumentation::Events::WEBHOOK_RECEIVED) do
      context = create_context_with_request(
        method: :post,
        body: echo_payload(app_id: nil)
      )
      @gateway.call(context)
    end

    assert_equal 1, events.size
    assert_equal :human_agent, events.first[:echo_origin]
  end

  def test_echo_from_our_own_app
    @mock_config.app_id = "our_app"
    events = capture_events(FlowChat::Instrumentation::Events::WEBHOOK_RECEIVED) do
      context = create_context_with_request(method: :post, body: echo_payload(app_id: "our_app"))
      @gateway.call(context)
    end

    assert_equal :self, events.first[:echo_origin]
  end

  def test_echo_from_another_app
    @mock_config.app_id = "our_app"
    events = capture_events(FlowChat::Instrumentation::Events::WEBHOOK_RECEIVED) do
      context = create_context_with_request(method: :post, body: echo_payload(app_id: "someone_else"))
      @gateway.call(context)
    end

    assert_equal :other_app, events.first[:echo_origin]
  end

  def test_non_echo_field_has_no_echo_origin
    events = capture_events(FlowChat::Instrumentation::Events::WEBHOOK_RECEIVED) do
      context = create_context_with_request(
        method: :post,
        body: {"entry" => [{"id" => "biz_1", "changes" => [{"field" => "account_update", "value" => {"event" => "PARTNER_ADDED"}}]}]}
      )
      @gateway.call(context)
    end

    refute events.first.key?(:echo_origin)
  end

  private

  def echo_payload(app_id:)
    value = {
      "metadata" => {"display_phone_number" => "+15551234567", "phone_number_id" => "test_phone_id"},
      "message_echoes" => [{"id" => "wamid.echo1", "from" => "15551234567", "type" => "text", "text" => {"body" => "Hi"}}]
    }
    value["message_echoes"][0]["app_id"] = app_id if app_id

    {"entry" => [{"id" => "biz_1", "changes" => [{"field" => "smb_message_echoes", "value" => value}]}]}
  end
```

Use the file's existing event-capture helper. If none exists, add one that subscribes with `ActiveSupport::Notifications.subscribe`, collects payloads, and unsubscribes in `teardown` (the file already tracks `@subscribers` for this).

- [ ] **Step 2: Run and watch them fail**

Run: `ruby -Itest test/unit/whatsapp/gateway/cloud_api_test.rb -n /echo/`
Expected: FAIL. `echo_origin` is not in the payload.

- [ ] **Step 3: Implement the derivation**

In `lib/flow_chat/whatsapp/gateway/cloud_api.rb`, extend `handle_unmodelled_field`:

```ruby
        def handle_unmodelled_field(field, value, business_account_id)
          FlowChat.logger.info {
            "CloudApi: Publishing webhook field '#{field}' (value keys: #{value.keys.join(", ")})"
          }

          payload = {
            platform: :whatsapp,
            gateway: :whatsapp_cloud_api,
            field: field,
            business_account_id: business_account_id,
            business_phone_number: value.dig("metadata", "display_phone_number"),
            business_phone_number_id: value.dig("metadata", "phone_number_id"),
            value: value
          }

          origin = echo_origin(field, value)
          payload[:echo_origin] = origin if origin

          instrument(Events::WEBHOOK_RECEIVED, payload)
        end

        # An echo reports a message sent on the thread by someone other than the
        # person we are talking to. Which someone matters: a human replying from
        # the business inbox usually means the application should stop the flow,
        # while our own send coming back means nothing at all. Only the app_id
        # separates them, and only this gateway knows our own.
        def echo_origin(field, value)
          return nil unless field.to_s.include?("echo")

          echoes = value.values.find { |v| v.is_a?(Array) && v.first.is_a?(Hash) }
          app_id = echoes&.first&.dig("app_id")

          return :human_agent if app_id.blank?
          return :self if app_id.to_s == @config.app_id.to_s

          :other_app
        end
```

- [ ] **Step 4: Run the tests**

Run: `ruby -Itest test/unit/whatsapp/gateway/cloud_api_test.rb`
Expected: PASS, 4 new tests green.

- [ ] **Step 5: Run the full suite**

Run: `bundle exec rake test`
Expected: PASS, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add lib/flow_chat/whatsapp/gateway/cloud_api.rb test/unit/whatsapp/gateway/cloud_api_test.rb
git commit -m "feat(whatsapp): say who sent an echo

An echo carrying no app_id is a human replying from the business inbox,
which usually means the application wants the flow to stand down. One
carrying our own app_id is just our send coming back. Only this gateway
knows our app_id, so it derives the origin rather than leaving every
subscriber to compare ids itself."
```

---

# Phase 2: Messenger

## Task 8: Messenger configuration

**Goal:** Credentials for Messenger, loadable from Rails credentials or environment, with the platform's limits as named constants.

**Files:**
- Create: `lib/flow_chat/messenger/configuration.rb`
- Create: `test/unit/messenger/configuration_test.rb`
- Modify: `lib/flow_chat/config.rb` (add `Config.messenger`)

**Acceptance Criteria:**
- [ ] `FlowChat::Messenger::Configuration` carries `page_id`, `access_token`, `verify_token`, `app_id`, `app_secret`, `skip_signature_validation`
- [ ] `from_credentials` reads `messenger:` from Rails credentials, falling back to `MESSENGER_*` env vars
- [ ] `valid?` is true only with `access_token`, `page_id` and `verify_token` all present
- [ ] `messages_url` is `"#{api_base_url}/#{page_id}/messages"`
- [ ] `FlowChat::Config.messenger` exposes `api_base_url`, `max_text_length`, `max_quick_replies`, `max_carousel_elements`, `max_buttons_per_element`

**Verify:** `ruby -Itest test/unit/messenger/configuration_test.rb` → PASS

**Steps:**

- [ ] **Step 1: Write the failing test**

Create `test/unit/messenger/configuration_test.rb`:

```ruby
require "test_helper"

class MessengerConfigurationTest < Minitest::Test
  def teardown
    FlowChat::Messenger::Configuration.clear_all!
  end

  def test_valid_requires_token_page_and_verify_token
    config = FlowChat::Messenger::Configuration.new(nil)
    refute config.valid?

    config.access_token = "tok"
    config.page_id = "page_1"
    refute config.valid?, "verify_token is still missing"

    config.verify_token = "verify"
    assert config.valid?
  end

  def test_messages_url_uses_the_page_id
    config = FlowChat::Messenger::Configuration.new(nil)
    config.page_id = "page_1"

    assert_equal "#{FlowChat::Config.messenger.api_base_url}/page_1/messages", config.messages_url
  end

  def test_from_credentials_reads_environment
    ENV["MESSENGER_ACCESS_TOKEN"] = "env_token"
    ENV["MESSENGER_PAGE_ID"] = "env_page"
    ENV["MESSENGER_VERIFY_TOKEN"] = "env_verify"
    ENV["MESSENGER_APP_SECRET"] = "env_secret"

    config = FlowChat::Messenger::Configuration.from_credentials

    assert_equal "env_token", config.access_token
    assert_equal "env_page", config.page_id
    assert_equal "env_secret", config.app_secret
    assert config.valid?
  ensure
    %w[MESSENGER_ACCESS_TOKEN MESSENGER_PAGE_ID MESSENGER_VERIFY_TOKEN MESSENGER_APP_SECRET].each { |k| ENV.delete(k) }
  end

  def test_registers_by_name
    config = FlowChat::Messenger::Configuration.new(:acme)

    assert_same config, FlowChat::Messenger::Configuration.get(:acme)
  end
end
```

- [ ] **Step 2: Run and watch it fail**

Run: `ruby -Itest test/unit/messenger/configuration_test.rb`
Expected: FAIL with `NameError: uninitialized constant FlowChat::Messenger`.

- [ ] **Step 3: Add the global config object**

In `lib/flow_chat/config.rb`, add the accessor next to `self.whatsapp`:

```ruby
    # Messenger-specific configuration object
    def self.messenger
      @messenger ||= MessengerConfig.new
    end
```

And the class next to `WhatsappConfig`:

```ruby
    class MessengerConfig
      attr_reader :api_base_url, :max_text_length, :max_quick_replies,
        :max_carousel_elements, :max_buttons_per_element,
        :max_quick_reply_title, :max_button_title, :max_element_title

      def initialize
        @api_base_url = "https://graph.facebook.com/v23.0"
        @max_text_length = 2000
        @max_quick_replies = 13
        @max_quick_reply_title = 20
        @max_carousel_elements = 10
        @max_buttons_per_element = 3
        @max_button_title = 20
        @max_element_title = 80
      end
    end
```

- [ ] **Step 4: Write the configuration class**

Create `lib/flow_chat/messenger/configuration.rb`:

```ruby
module FlowChat
  module Messenger
    class ConfigurationError < StandardError; end

    class Configuration
      include FlowChat::NamedConfiguration

      attr_accessor :access_token, :page_id, :verify_token, :app_id, :app_secret,
        :name, :skip_signature_validation

      def initialize(name)
        @name = name
        @skip_signature_validation = false

        FlowChat.logger.debug { "Messenger::Configuration: Initialized configuration with name: #{name || "anonymous"}" }

        register_as(name) if name.present?
      end

      def self.from_credentials
        FlowChat.logger.info { "Messenger::Configuration: Loading configuration from credentials/environment" }

        config = new(nil)

        if defined?(Rails) && Rails.respond_to?(:application) && Rails.application&.credentials&.messenger
          credentials = Rails.application.credentials.messenger
          config.access_token = credentials[:access_token]
          config.page_id = credentials[:page_id]
          config.verify_token = credentials[:verify_token]
          config.app_id = credentials[:app_id]
          config.app_secret = credentials[:app_secret]
          config.skip_signature_validation = credentials[:skip_signature_validation] || false
        else
          config.access_token = ENV["MESSENGER_ACCESS_TOKEN"]
          config.page_id = ENV["MESSENGER_PAGE_ID"]
          config.verify_token = ENV["MESSENGER_VERIFY_TOKEN"]
          config.app_id = ENV["MESSENGER_APP_ID"]
          config.app_secret = ENV["MESSENGER_APP_SECRET"]
          config.skip_signature_validation = ENV["MESSENGER_SKIP_SIGNATURE_VALIDATION"] == "true"
        end

        config
      end

      def valid?
        access_token.present? && page_id.present? && verify_token.present?
      end

      # The account this configuration speaks for. Named generically so the
      # shared gateway can check it without knowing which platform it holds.
      def account_id
        page_id
      end

      def messages_url
        "#{api_base_url}/#{page_id}/messages"
      end

      def attachment_upload_url
        "#{api_base_url}/#{page_id}/message_attachments"
      end

      def api_base_url
        FlowChat::Config.messenger.api_base_url
      end

      def api_headers
        {
          "Authorization" => "Bearer #{access_token}",
          "Content-Type" => "application/json"
        }
      end
    end
  end
end
```

- [ ] **Step 5: Run the test**

Run: `ruby -Itest test/unit/messenger/configuration_test.rb`
Expected: PASS, 4 tests.

- [ ] **Step 6: Commit**

```bash
git add lib/flow_chat/messenger/configuration.rb lib/flow_chat/config.rb test/unit/messenger/configuration_test.rb
git commit -m "feat(messenger): configure the page a gateway speaks for"
```

---

## Task 9: The choice ladder helper

**Goal:** One place that decides which rung renders a given choice count, so the renderer and the choice mapper cannot disagree.

**Files:**
- Create: `lib/flow_chat/meta/choice_ladder.rb`
- Create: `test/unit/meta/choice_ladder_test.rb`

**Acceptance Criteria:**
- [ ] `rung_for(count, limits)` returns `:quick_replies`, `:carousel` or `:numbered`
- [ ] `count` of 0 returns `:none`
- [ ] With Messenger limits: 13 is `:quick_replies`, 14 is `:carousel`, 30 is `:carousel`, 31 is `:numbered`
- [ ] `numbers_in_body?` is true on the `:numbered` rung, and true on every rung when `always_number:` is set

**Verify:** `ruby -Itest test/unit/meta/choice_ladder_test.rb` → PASS

**Steps:**

- [ ] **Step 1: Write the failing test**

Create `test/unit/meta/choice_ladder_test.rb`:

```ruby
require "test_helper"

class ChoiceLadderTest < Minitest::Test
  def setup
    @limits = FlowChat::Config.messenger
  end

  def test_no_choices
    assert_equal :none, FlowChat::Meta::ChoiceLadder.rung_for(0, @limits)
  end

  def test_quick_replies_up_to_thirteen
    assert_equal :quick_replies, FlowChat::Meta::ChoiceLadder.rung_for(1, @limits)
    assert_equal :quick_replies, FlowChat::Meta::ChoiceLadder.rung_for(13, @limits)
  end

  def test_carousel_between_fourteen_and_thirty
    assert_equal :carousel, FlowChat::Meta::ChoiceLadder.rung_for(14, @limits)
    assert_equal :carousel, FlowChat::Meta::ChoiceLadder.rung_for(30, @limits)
  end

  def test_numbered_above_the_carousel_capacity
    assert_equal :numbered, FlowChat::Meta::ChoiceLadder.rung_for(31, @limits)
    assert_equal :numbered, FlowChat::Meta::ChoiceLadder.rung_for(200, @limits)
  end

  def test_numbers_in_body_on_the_numbered_rung
    assert FlowChat::Meta::ChoiceLadder.numbers_in_body?(31, @limits)
    refute FlowChat::Meta::ChoiceLadder.numbers_in_body?(5, @limits)
  end

  # Instagram renders quick replies and carousels on mobile only, so its
  # renderer numbers the body at every rung.
  def test_always_number_covers_every_rung
    assert FlowChat::Meta::ChoiceLadder.numbers_in_body?(5, @limits, always_number: true)
    assert FlowChat::Meta::ChoiceLadder.numbers_in_body?(20, @limits, always_number: true)
    refute FlowChat::Meta::ChoiceLadder.numbers_in_body?(0, @limits, always_number: true)
  end
end
```

- [ ] **Step 2: Run and watch it fail**

Run: `ruby -Itest test/unit/meta/choice_ladder_test.rb`
Expected: FAIL with `NameError: uninitialized constant FlowChat::Meta::ChoiceLadder`.

- [ ] **Step 3: Implement it**

Create `lib/flow_chat/meta/choice_ladder.rb`:

```ruby
module FlowChat
  module Meta
    # Which interactive surface renders a given number of choices.
    #
    # The renderer and the choice mapper both need this answer, and they must
    # agree: the renderer decides what the user sees, the mapper decides what a
    # reply is allowed to mean. Two copies of the arithmetic would drift into a
    # screen whose replies cannot be resolved.
    module ChoiceLadder
      def self.rung_for(count, limits)
        return :none if count.zero?
        return :quick_replies if count <= limits.max_quick_replies
        return :carousel if count <= carousel_capacity(limits)

        :numbered
      end

      # The carousel holds elements, each holding buttons, and one option is one
      # button.
      def self.carousel_capacity(limits)
        limits.max_carousel_elements * limits.max_buttons_per_element
      end

      # Whether the options are also listed, numbered, in the message body.
      #
      # always_number is for platforms whose interactive surfaces do not render
      # everywhere. Without it a user who cannot see the buttons has no way to
      # answer at all.
      def self.numbers_in_body?(count, limits, always_number: false)
        return false if count.zero?
        return true if always_number

        rung_for(count, limits) == :numbered
      end
    end
  end
end
```

- [ ] **Step 4: Run the test**

Run: `ruby -Itest test/unit/meta/choice_ladder_test.rb`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/flow_chat/meta/choice_ladder.rb test/unit/meta/choice_ladder_test.rb
git commit -m "feat(meta): decide the choice rung in one place"
```

---

## Task 10: Messenger renderer

**Goal:** Turn `[prompt, choices, media]` into a Send API payload shape, down the ladder, in plain text.

**Files:**
- Create: `lib/flow_chat/messenger/renderer.rb`
- Create: `test/unit/messenger/renderer_test.rb`

**Acceptance Criteria:**
- [ ] No choices renders `[:text, plain_text, {}]`
- [ ] 1 to 13 choices render `[:quick_replies, text, {quick_replies: [{content_type:, title:, payload:}]}]` with titles truncated to 20
- [ ] 14 to 30 choices render `[:carousel, text, {elements: [...]}]` with at most 10 elements of at most 3 `postback` buttons
- [ ] Above 30 choices renders `[:text, text_with_numbered_options, {}]`
- [ ] Markdown in the prompt is flattened: `**bold**` arrives as `bold`
- [ ] Media with no choices renders `[:attachment, caption, {type:, url:}]`

**Verify:** `ruby -Itest test/unit/messenger/renderer_test.rb` → PASS

**Steps:**

- [ ] **Step 1: Write the failing test**

Create `test/unit/messenger/renderer_test.rb`:

```ruby
require "test_helper"

class MessengerRendererTest < Minitest::Test
  def render(message, choices: nil, media: nil)
    FlowChat::Messenger::Renderer.new(message, choices: choices, media: media).render
  end

  def test_plain_text_message
    result = render("Hello **world**")

    assert_equal :text, result[0]
    assert_equal "Hello world", result[1]
    assert_equal({}, result[2])
  end

  def test_quick_replies_for_thirteen_or_fewer
    choices = (1..13).to_h { |i| ["k#{i}", "Option #{i}"] }

    result = render("Pick one", choices: choices)

    assert_equal :quick_replies, result[0]
    assert_equal 13, result[2][:quick_replies].length
    assert_equal "text", result[2][:quick_replies][0][:content_type]
    assert_equal "Option 1", result[2][:quick_replies][0][:title]
    assert_equal "k1", result[2][:quick_replies][0][:payload]
  end

  def test_quick_reply_titles_truncate_at_twenty
    result = render("Pick", choices: {"k" => "A title that is definitely longer than twenty"})

    assert_equal 20, result[2][:quick_replies][0][:title].length
  end

  def test_carousel_between_fourteen_and_thirty
    choices = (1..14).to_h { |i| ["k#{i}", "Option #{i}"] }

    result = render("Pick one", choices: choices)

    assert_equal :carousel, result[0]
    assert_equal 5, result[2][:elements].length
    assert_equal 3, result[2][:elements][0][:buttons].length
    assert_equal "postback", result[2][:elements][0][:buttons][0][:type]
    assert_equal "k1", result[2][:elements][0][:buttons][0][:payload]
  end

  def test_carousel_never_exceeds_ten_elements
    choices = (1..30).to_h { |i| ["k#{i}", "Option #{i}"] }

    result = render("Pick one", choices: choices)

    assert_equal :carousel, result[0]
    assert_equal 10, result[2][:elements].length
    assert_equal 30, result[2][:elements].sum { |e| e[:buttons].length }
  end

  def test_numbered_body_above_thirty
    choices = (1..31).to_h { |i| ["k#{i}", "Option #{i}"] }

    result = render("Pick one", choices: choices)

    assert_equal :text, result[0]
    assert_includes result[1], "1. Option 1"
    assert_includes result[1], "31. Option 31"
  end

  def test_attachment_without_choices
    result = render("A caption", media: {type: :image, url: "https://example.com/a.png"})

    assert_equal :attachment, result[0]
    assert_equal "A caption", result[1]
    assert_equal :image, result[2][:type]
    assert_equal "https://example.com/a.png", result[2][:url]
  end
end
```

- [ ] **Step 2: Run and watch it fail**

Run: `ruby -Itest test/unit/messenger/renderer_test.rb`
Expected: FAIL with `NameError: uninitialized constant FlowChat::Messenger::Renderer`.

- [ ] **Step 3: Implement the renderer**

Create `lib/flow_chat/messenger/renderer.rb`:

```ruby
require "flow_chat/renderers/markdown_support"

module FlowChat
  module Messenger
    class Renderer
      include FlowChat::Renderers::MarkdownSupport

      attr_reader :message, :choices, :media

      def initialize(message, choices: nil, media: nil)
        @message = message
        @choices = choices
        @media = media
      end

      def render
        return build_attachment if media && choices.blank?

        case FlowChat::Meta::ChoiceLadder.rung_for(choice_count, limits)
        when :none then build_text
        when :quick_replies then build_quick_replies
        when :carousel then build_carousel
        when :numbered then build_numbered
        end
      end

      private

      def limits
        FlowChat::Config.messenger
      end

      def always_number?
        false
      end

      def choice_count
        choices.is_a?(Hash) ? choices.length : 0
      end

      # Neither Messenger nor Instagram renders markup, so the prompt is
      # flattened rather than translated.
      def body
        text = to_plain_text(message)
        return text unless FlowChat::Meta::ChoiceLadder.numbers_in_body?(choice_count, limits, always_number: always_number?)

        "#{text}\n\n#{numbered_options}"
      end

      def numbered_options
        choices.values.map.with_index(1) { |label, i| "#{i}. #{label}" }.join("\n")
      end

      def build_text
        [:text, body, {}]
      end

      def build_numbered
        [:text, body, {}]
      end

      def build_quick_replies
        replies = choices.map do |key, label|
          {
            content_type: "text",
            title: truncate_text(label.to_s, limits.max_quick_reply_title),
            payload: key.to_s
          }
        end

        [:quick_replies, body, {quick_replies: replies}]
      end

      # One option is one button, and buttons live on elements, so the options
      # are packed across elements rather than one element per option.
      def build_carousel
        elements = choices.each_slice(limits.max_buttons_per_element).map.with_index(1) do |slice, index|
          first = (index - 1) * limits.max_buttons_per_element + 1
          last = first + slice.length - 1

          {
            title: truncate_text("Options #{first} to #{last}", limits.max_element_title),
            buttons: slice.map do |key, label|
              {
                type: "postback",
                title: truncate_text(label.to_s, limits.max_button_title),
                payload: key.to_s
              }
            end
          }
        end

        [:carousel, body, {elements: elements}]
      end

      def build_attachment
        type = (media[:type] || :image).to_sym
        options = {type: type}
        options[:url] = media[:url] if media[:url]
        options[:attachment_id] = media[:id] if media[:id]

        [:attachment, to_plain_text(message), options]
      end

      def truncate_text(text, length)
        return text if text.length <= length
        text[0, length - 3] + "..."
      end
    end
  end
end
```

- [ ] **Step 4: Run the test**

Run: `ruby -Itest test/unit/messenger/renderer_test.rb`
Expected: PASS, 8 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/flow_chat/messenger/renderer.rb test/unit/messenger/renderer_test.rb
git commit -m "feat(messenger): render prompts down the choice ladder"
```

---

## Task 11: Messenger client

**Goal:** Send to the Send API, splitting text that exceeds the platform cap, and report failures through the existing delivery hooks.

**Files:**
- Create: `lib/flow_chat/messenger/client.rb`
- Create: `test/unit/messenger/client_test.rb`

**Acceptance Criteria:**
- [ ] `send_message(recipient_id, prompt, choices:, media:)` posts to `config.messages_url`
- [ ] The payload is `{recipient: {id:}, messaging_type: "RESPONSE", message: {...}}`
- [ ] Quick replies attach to the text message; a carousel posts an `attachment` with `template_type: "generic"`
- [ ] Text longer than `max_text_length` is sent as several messages, split on whitespace, and the last result is returned
- [ ] A non-2xx response reports `API_ERROR` and returns `nil`
- [ ] `upload_media` posts to `config.attachment_upload_url` and returns the `attachment_id`

**Verify:** `ruby -Itest test/unit/messenger/client_test.rb` → PASS

**Steps:**

- [ ] **Step 1: Write the failing test**

Create `test/unit/messenger/client_test.rb`:

```ruby
require "test_helper"
require "webmock/minitest"

class MessengerClientTest < Minitest::Test
  def setup
    @config = FlowChat::Messenger::Configuration.new(nil)
    @config.page_id = "page_1"
    @config.access_token = "tok"
    @config.verify_token = "verify"
    @client = FlowChat::Messenger::Client.new(@config)

    WebMock.enable!
    WebMock.reset!
    stub_request(:post, @config.messages_url)
      .to_return(status: 200, body: {"recipient_id" => "psid_1", "message_id" => "mid.1"}.to_json)
  end

  def teardown
    WebMock.disable!
    WebMock.reset!
  end

  def test_sends_text_with_the_send_api_shape
    result = @client.send_message("psid_1", "Hello")

    assert_equal "mid.1", result["message_id"]
    assert_requested(:post, @config.messages_url) do |req|
      body = JSON.parse(req.body)
      body["recipient"] == {"id" => "psid_1"} &&
        body["messaging_type"] == "RESPONSE" &&
        body["message"] == {"text" => "Hello"}
    end
  end

  def test_quick_replies_ride_on_the_text_message
    @client.send_message("psid_1", "Pick", choices: {"a" => "Alpha", "b" => "Beta"})

    assert_requested(:post, @config.messages_url) do |req|
      message = JSON.parse(req.body)["message"]
      message["text"] == "Pick" && message["quick_replies"].length == 2
    end
  end

  def test_carousel_posts_a_generic_template
    choices = (1..14).to_h { |i| ["k#{i}", "Option #{i}"] }

    @client.send_message("psid_1", "Pick", choices: choices)

    assert_requested(:post, @config.messages_url) do |req|
      payload = JSON.parse(req.body).dig("message", "attachment", "payload")
      payload["template_type"] == "generic" && payload["elements"].length == 5
    end
  end

  def test_long_text_is_split_into_several_sends
    long = "word " * 600 # comfortably over 2000 characters

    @client.send_message("psid_1", long)

    assert_requested(:post, @config.messages_url, times: 2)
  end

  def test_failed_request_returns_nil
    WebMock.reset!
    stub_request(:post, @config.messages_url).to_return(status: 400, body: '{"error":{"message":"bad"}}')

    assert_nil @client.send_message("psid_1", "Hello")
  end
end
```

- [ ] **Step 2: Run and watch it fail**

Run: `ruby -Itest test/unit/messenger/client_test.rb`
Expected: FAIL with `NameError: uninitialized constant FlowChat::Messenger::Client`.

- [ ] **Step 3: Implement the client**

Create `lib/flow_chat/messenger/client.rb`:

```ruby
require "net/http"
require "json"
require "uri"

module FlowChat
  module Messenger
    class Client
      include FlowChat::Instrumentation

      def initialize(config)
        @config = config
        FlowChat.logger.info { "Messenger::Client: Initialized for page_id: #{@config.page_id}" }
      end

      def send_message(recipient_id, prompt, choices: nil, media: nil)
        response = renderer_class.new(prompt, choices: choices, media: media).render
        type, content, options = response

        instrument(Events::MESSAGE_SENT, {
          to: recipient_id,
          message_type: type.to_s,
          content_length: content.to_s.length,
          platform: platform
        }) do
          deliver(recipient_id, type, content, options)
        end
      end

      def send_text(recipient_id, text)
        send_message(recipient_id, text)
      end

      # Uploads a file for reuse and returns the id Meta assigned it.
      def upload_media(url, type: :image)
        payload = {
          message: {
            attachment: {
              type: type.to_s,
              payload: {url: url, is_reusable: true}
            }
          }
        }

        result = post_json(@config.attachment_upload_url, payload)
        result && result["attachment_id"]
      end

      private

      def renderer_class
        FlowChat::Messenger::Renderer
      end

      def platform
        :messenger
      end

      def limits
        FlowChat::Config.messenger
      end

      # Anything over the platform's cap is rejected whole rather than trimmed by
      # Meta, so long text goes as several messages. Only the last result is
      # returned: it carries the id of the message the user ends up looking at.
      def deliver(recipient_id, type, content, options)
        case type
        when :text
          split_text(content).map { |chunk| post_message(recipient_id, {text: chunk}) }.last
        when :quick_replies
          chunks = split_text(content)
          # Quick replies belong on the final chunk, next to the question.
          chunks[0..-2].each { |chunk| post_message(recipient_id, {text: chunk}) }
          post_message(recipient_id, {text: chunks.last, quick_replies: options[:quick_replies]})
        when :carousel
          post_message(recipient_id, {text: content}) if content.present?
          post_message(recipient_id, {
            attachment: {
              type: "template",
              payload: {template_type: "generic", elements: options[:elements]}
            }
          })
        when :attachment
          attachment_payload = options[:url] ? {url: options[:url], is_reusable: true} : {attachment_id: options[:attachment_id]}
          post_message(recipient_id, {text: content}) if content.present?
          post_message(recipient_id, {
            attachment: {type: options[:type].to_s, payload: attachment_payload}
          })
        end
      end

      def post_message(recipient_id, message)
        post_json(@config.messages_url, {
          recipient: {id: recipient_id},
          messaging_type: "RESPONSE",
          message: message
        })
      end

      # Splits on whitespace so a word is never cut in half. Measured with the
      # platform's own unit, which is bytes on Instagram and characters here.
      def split_text(text)
        limit = limits.max_text_length
        return [text.to_s] if measure(text.to_s) <= limit

        chunks = []
        current = ""

        text.to_s.split(/(\s+)/).each do |piece|
          if measure(current + piece) > limit && current.present?
            chunks << current.strip
            current = piece.lstrip
          else
            current += piece
          end
        end

        chunks << current.strip if current.strip.present?
        chunks
      end

      def measure(string)
        string.length
      end

      def post_json(url, payload)
        uri = URI(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri)
        @config.api_headers.each { |key, value| request[key] = value }
        request.body = payload.to_json

        response = http.request(request)

        if response.is_a?(Net::HTTPSuccess)
          JSON.parse(response.body)
        else
          FlowChat.logger.error { "#{self.class.name}: API request failed - #{response.code}: #{response.body}" }
          report_api_error(
            "#{platform} API request failed",
            response_code: response.code,
            response_body: response.body
          )
          nil
        end
      rescue Net::OpenTimeout, Net::ReadTimeout => network_error
        FlowChat.logger.error { "#{self.class.name}: Network timeout: #{network_error.class.name}" }
        raise network_error
      end
    end
  end
end
```

Check `report_api_error`'s exact signature in `lib/flow_chat/instrumentation.rb` before wiring it, and match the keyword arguments the WhatsApp client passes at `whatsapp/client.rb:540`.

- [ ] **Step 4: Run the test**

Run: `ruby -Itest test/unit/messenger/client_test.rb`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/flow_chat/messenger/client.rb test/unit/messenger/client_test.rb
git commit -m "feat(messenger): send through the Send API"
```

---

## Task 12: The shared messaging gateway

**Goal:** The `entry[].messaging[]` envelope, dispatch, echo classification, delivery receipts, and context population, implemented once for both platforms.

**Files:**
- Create: `lib/flow_chat/meta/messaging_gateway.rb`
- Create: `test/unit/meta/messaging_gateway_test.rb`
- Modify: `lib/flow_chat/session/middleware.rb:93-102`

**Acceptance Criteria:**
- [ ] A text message sets `request.id`, `request.user_id`, `request.message_id`, `request.platform`, `request.gateway`, `context.input`
- [ ] `request.msisdn` is `nil`
- [ ] A `quick_reply` payload becomes `context.input`
- [ ] A `postback` payload becomes `context.input` and drives the flow
- [ ] An echo never drives the flow and is published with `echo_origin`
- [ ] `delivery` and `read` publish `MESSAGE_STATUS` and are handled before the flow slot is claimed
- [ ] Only one event per delivery drives a flow, and a second logs a warning
- [ ] An event for an account other than the configured one is rejected with `:forbidden`
- [ ] `platform_default_identifier` returns `:user_id` for `:messenger` and `:instagram`

**Verify:** `ruby -Itest test/unit/meta/messaging_gateway_test.rb` → PASS

**Steps:**

- [ ] **Step 1: Write the failing test**

Create `test/unit/meta/messaging_gateway_test.rb`. The test defines its own concrete subclass so the base class is exercised without depending on Task 13:

```ruby
require "test_helper"

class MessagingGatewayTest < Minitest::Test
  # The base class is abstract. This exercises it directly rather than through
  # a platform, so a failure here is unambiguously the envelope's fault.
  class TestGateway < FlowChat::Meta::MessagingGateway
    def platform = :messenger
    def gateway_name = :messenger_send_api
    def configuration_class = FlowChat::Messenger::Configuration
    def client_class = FlowChat::Messenger::Client
    def renderer_class = FlowChat::Messenger::Renderer
    def self.choice_mapper_class = FlowChat::Messenger::Middleware::ChoiceMapper
  end

  def setup
    @config = FlowChat::Messenger::Configuration.new(nil)
    @config.page_id = "page_1"
    @config.access_token = "tok"
    @config.verify_token = "verify"
    @config.app_id = "our_app"
    @config.skip_signature_validation = true

    @app = proc { |context| [:text, "Response", nil, nil] }
    @gateway = TestGateway.new(@app, @config)
    @sent = []
    @gateway.client.define_singleton_method(:send_message) do |*args, **kwargs|
      {"message_id" => "mid.sent"}
    end
  end

  def test_text_message_populates_context
    context = post(messaging_payload({"message" => {"mid" => "mid.1", "text" => "Hello"}}))

    assert_equal "Hello", context.input
    assert_equal "psid_1", context["request.user_id"]
    assert_equal "psid_1", context["request.id"]
    assert_equal "mid.1", context["request.message_id"]
    assert_equal :messenger, context["request.platform"]
    assert_equal :messenger_send_api, context["request.gateway"]
    assert_nil context["request.msisdn"]
  end

  def test_quick_reply_payload_is_the_input
    context = post(messaging_payload({
      "message" => {"mid" => "mid.2", "text" => "Alpha", "quick_reply" => {"payload" => "choice_a"}}
    }))

    assert_equal "choice_a", context.input
  end

  def test_postback_payload_is_the_input
    context = post(messaging_payload({"postback" => {"mid" => "mid.3", "payload" => "get_started"}}))

    assert_equal "get_started", context.input
  end

  def test_echo_never_drives_a_flow_and_reports_its_origin
    events = capture_webhook_received do
      post(messaging_payload({
        "message" => {"mid" => "mid.4", "text" => "From a human", "is_echo" => true}
      }))
    end

    assert_equal 1, events.size
    assert_equal :human_agent, events.first[:echo_origin]
  end

  def test_echo_from_our_own_app_is_labelled_self
    events = capture_webhook_received do
      post(messaging_payload({
        "message" => {"mid" => "mid.5", "text" => "Ours", "is_echo" => true, "app_id" => "our_app"}
      }))
    end

    assert_equal :self, events.first[:echo_origin]
  end

  def test_delivery_receipt_publishes_status_and_leaves_the_flow_slot
    statuses = capture_events(FlowChat::Instrumentation::Events::MESSAGE_STATUS) do
      context = post({
        "object" => "page",
        "entry" => [{
          "id" => "page_1",
          "messaging" => [
            {"sender" => {"id" => "psid_1"}, "recipient" => {"id" => "page_1"}, "delivery" => {"mids" => ["mid.1"], "watermark" => 1}},
            {"sender" => {"id" => "psid_1"}, "recipient" => {"id" => "page_1"}, "message" => {"mid" => "mid.6", "text" => "Still here"}}
          ]
        }]
      })

      assert_equal "Still here", context.input, "a receipt must not spend the flow slot"
    end

    assert_equal 1, statuses.size
  end

  def test_second_message_in_one_delivery_does_not_run
    context = post({
      "object" => "page",
      "entry" => [{
        "id" => "page_1",
        "messaging" => [
          {"sender" => {"id" => "psid_1"}, "recipient" => {"id" => "page_1"}, "message" => {"mid" => "mid.7", "text" => "First"}},
          {"sender" => {"id" => "psid_2"}, "recipient" => {"id" => "page_1"}, "message" => {"mid" => "mid.8", "text" => "Second"}}
        ]
      }]
    })

    assert_equal "First", context.input
  end

  def test_event_for_another_account_is_rejected
    context = post({
      "object" => "page",
      "entry" => [{
        "id" => "someone_elses_page",
        "messaging" => [{"sender" => {"id" => "psid_1"}, "recipient" => {"id" => "someone_elses_page"}, "message" => {"mid" => "m", "text" => "Hi"}}]
      }]
    })

    assert_equal :forbidden, context.controller.last_head_status
  end

  def test_session_identifier_defaults_to_user_id
    middleware = FlowChat::Session::Middleware.allocate
    context = FlowChat::Context.new
    context["request.platform"] = :messenger

    assert_equal :user_id, middleware.send(:platform_default_identifier, context)
  end

  private

  def messaging_payload(event)
    {
      "object" => "page",
      "entry" => [{
        "id" => "page_1",
        "messaging" => [
          {"sender" => {"id" => "psid_1"}, "recipient" => {"id" => "page_1"}, "timestamp" => 1_700_000_000}.merge(event)
        ]
      }]
    }
  end

  def post(body)
    context = build_messaging_context(body)
    @gateway.call(context)
    context
  end
end
```

Add `build_messaging_context(body)`, `capture_events(event_name)` and `capture_webhook_received` to `test/support/test_helpers.rb` so phases 2 and 3 share them. `build_messaging_context` mirrors `create_context_with_request` from `test/unit/whatsapp/gateway/cloud_api_test.rb:851`: an `OpenStruct` request with `post?`, `get?`, `body` as a rewindable `StringIO`, `headers`, `cookies`, and a controller recording `render`, `head` and `last_head_status`.

- [ ] **Step 2: Run and watch it fail**

Run: `ruby -Itest test/unit/meta/messaging_gateway_test.rb`
Expected: FAIL with `NameError: uninitialized constant FlowChat::Meta::MessagingGateway`.

- [ ] **Step 3: Implement the base gateway**

Create `lib/flow_chat/meta/messaging_gateway.rb`:

```ruby
require "json"

module FlowChat
  module Meta
    # The Messenger Platform envelope, shared by Facebook Messenger and
    # Instagram DMs. Both deliver entry[].messaging[] and both send through the
    # same Send API, so the envelope is implemented once and each platform
    # supplies only what actually differs.
    class MessagingGateway
      include FlowChat::Instrumentation
      include FlowChat::GatewayAsyncSupport
      include FlowChat::Meta::SignatureValidation
      include FlowChat::Meta::WebhookVerification

      attr_reader :context, :client

      def initialize(app, config = nil)
        @app = app
        @config = config || configuration_class.from_credentials
        @client = client_class.new(@config)

        FlowChat.logger.info { "#{log_tag}: Initialized #{platform} gateway for account #{@config.account_id}" }
      end

      def call(context)
        @context = context
        @controller = context.controller
        request = @controller.request

        unless in_background?
          if request.get? && request.params["hub.mode"] == "subscribe"
            return handle_verification(context)
          end
        end

        return handle_webhook(context) if request.post?

        FlowChat.logger.warn { "#{log_tag}: Invalid request method or parameters - returning bad request" }
        @controller.head :bad_request
      end

      def self.configure_middleware_stack(builder, custom_middleware)
        builder.use custom_middleware
        builder.use choice_mapper_class
      end

      # --- Hooks each platform overrides ---

      def platform
        raise NotImplementedError
      end

      def gateway_name
        raise NotImplementedError
      end

      def configuration_class
        raise NotImplementedError
      end

      def client_class
        raise NotImplementedError
      end

      def renderer_class
        raise NotImplementedError
      end

      # Meta names the subscription this delivery came from. Messenger uses
      # "page". Instagram's value depends on how the app is set up, so each
      # platform states its own rather than sharing a guess.
      def expected_webhook_object
        "page"
      end

      private

      def handle_webhook(context)
        begin
          parse_request_body(@controller.request)
        rescue JSON::ParserError => e
          FlowChat.logger.error { "#{log_tag}: Failed to parse webhook body: #{e.message}" }
          return @controller.head :bad_request
        end

        is_simulator_mode = simulate?(context)
        context["simulator_mode"] = true if is_simulator_mode

        unless in_background? || is_simulator_mode || valid_webhook_signature?(@controller.request)
          FlowChat.logger.warn { "#{log_tag}: Invalid webhook signature - dropping request" }
          return @controller.head :ok
        end

        if @body["object"].present? && @body["object"] != expected_webhook_object
          FlowChat.logger.debug { "#{log_tag}: Ignoring webhook for object '#{@body["object"]}'" }
          return @controller.head :ok
        end

        entries = @body["entry"]
        unless entries.is_a?(Array) && entries.any?
          return @controller.head :ok
        end

        # Only one event per delivery can drive a flow, because only one can own
        # the response to this request.
        flow_ran = false

        entries.each do |entry|
          events = entry["messaging"] || entry["standby"]
          next unless events.is_a?(Array)

          # Receipts are handled before any flow claims the slot. A receipt
          # arriving ahead of a message in the same batch would otherwise spend
          # the slot and the message would be lost.
          events.each { |event| handle_status(entry, event) if status_event?(event) }

          events.each do |event|
            next if status_event?(event)

            if echo?(event)
              publish_echo(entry, event)
              next
            end

            unless drives_flow?(event)
              publish_unmodelled(entry, event)
              next
            end

            if flow_ran
              FlowChat.logger.warn { "#{log_tag}: A second message arrived in the same delivery and was not processed" }
              next
            end
            flow_ran = true

            case handle_message(context, entry, event)
            when :rejected then return @controller.head :forbidden
            when :enqueued then return @controller.head :ok
            when :rendered then return nil
            end
          end
        end

        @controller.head :ok
      end

      def status_event?(event)
        event.key?("delivery") || event.key?("read")
      end

      def echo?(event)
        event.dig("message", "is_echo") == true
      end

      def drives_flow?(event)
        event.key?("message") || event.key?("postback")
      end

      def handle_message(context, entry, event)
        account_id = entry["id"]
        if account_id.to_s != @config.account_id.to_s
          FlowChat.logger.warn { "#{log_tag}: Webhook for account '#{account_id}' but configured for '#{@config.account_id}' - rejecting" }
          return :rejected
        end

        sender_id = event.dig("sender", "id")
        message = event["message"] || event["postback"]

        context["request.id"] = sender_id
        context["request.user_id"] = sender_id
        context["request.msisdn"] = nil
        context["request.message_id"] = message["mid"]
        context["request.gateway"] = gateway_name
        context["request.platform"] = platform
        context["request.timestamp"] = Time.current.iso8601
        context["request.body"] = @body

        context["#{platform}.account.id"] = account_id
        context["#{platform}.client"] = @client

        extract_message_content!(event, context)

        instrument(Events::MESSAGE_RECEIVED, {
          from: sender_id,
          message: context.input,
          message_type: event.key?("postback") ? "postback" : "message",
          message_id: message["mid"]
        })

        return (enqueue_async_job || :enqueued) && :enqueued if should_enqueue_async?

        if context["simulator_mode"]
          handle_message_simulator(context)
          :rendered
        else
          handle_message_inline(context)
          :processed
        end
      end

      # A postback's payload, a quick reply's payload, and otherwise the text.
      # An attachment-only turn has blank input, matching the media contract the
      # other gateways follow.
      def extract_message_content!(event, context)
        if event.key?("postback")
          context.input = event.dig("postback", "payload").to_s
          return
        end

        message = event["message"]

        if message["quick_reply"]
          context.input = message.dig("quick_reply", "payload").to_s
          return
        end

        attachments = message["attachments"]
        if attachments.is_a?(Array) && attachments.any?
          attachment = attachments.first
          context["request.media"] = {
            type: normalize_attachment_type(attachment["type"]),
            url: attachment.dig("payload", "url")
          }
        end

        context.input = message["text"].presence || ""
      end

      # "file" is Meta's name for what every other gateway here calls a document.
      def normalize_attachment_type(type)
        case type.to_s
        when "file" then :document
        when "" then nil
        else type.to_s.to_sym
        end
      end

      def handle_status(entry, event)
        %w[delivery read].each do |kind|
          payload = event[kind]
          next unless payload

          instrument(Events::MESSAGE_STATUS, {
            platform: platform,
            gateway: gateway_name,
            account_id: entry["id"],
            recipient: event.dig("sender", "id"),
            status: kind,
            timestamp: event["timestamp"],
            value: payload
          })
        end
      end

      # An echo reports a message sent on this thread by someone other than the
      # user. Which someone decides what the application does about it: a human
      # replying from the page inbox usually means the flow should stand down.
      def publish_echo(entry, event)
        instrument(Events::WEBHOOK_RECEIVED, {
          platform: platform,
          gateway: gateway_name,
          field: "message_echoes",
          account_id: entry["id"],
          echo_origin: echo_origin(event),
          value: event
        })
      end

      def echo_origin(event)
        app_id = event.dig("message", "app_id")

        return :human_agent if app_id.blank?
        return :self if app_id.to_s == @config.app_id.to_s

        :other_app
      end

      # Everything that is not a message, its receipt, or an echo. Reactions,
      # referrals, opt-ins, handovers, policy enforcement: all of it is the
      # application's domain, so it is published whole rather than interpreted.
      def publish_unmodelled(entry, event)
        field = (event.keys - %w[sender recipient timestamp]).first

        FlowChat.logger.info { "#{log_tag}: Publishing webhook event '#{field}'" }

        instrument(Events::WEBHOOK_RECEIVED, {
          platform: platform,
          gateway: gateway_name,
          field: field,
          account_id: entry["id"],
          value: event
        })
      end

      def handle_message_inline(context)
        response = @app.call(context)
        return unless response

        type, prompt, choices, media = response

        result = report_delivery_failure(
          context,
          to: context["request.user_id"],
          session_id: context["request.id"],
          message: prompt,
          message_type: (type == :prompt) ? "prompt" : "terminal",
          gateway: gateway_name,
          platform: platform
        ) do
          @client.send_message(context["request.user_id"], prompt, choices: choices, media: media)
        end

        context["#{platform}.message_result"] = result

        instrument(Events::MESSAGE_SENT, {
          to: context["request.user_id"],
          session_id: context["request.id"],
          message: prompt,
          message_type: (type == :prompt) ? "prompt" : "terminal",
          gateway: gateway_name,
          platform: platform,
          content_length: prompt.to_s.length,
          platform_message_id: platform_message_id_from(result),
          timestamp: context["request.timestamp"]
        })
      end

      # The Send API answers with the id it assigned, flatter than WhatsApp's
      # messages[0].id.
      def platform_message_id_from(result)
        return nil unless result.is_a?(Hash)

        result["message_id"]
      end

      def handle_message_simulator(context)
        response = @app.call(context)
        return unless response

        _, prompt, choices, media = response
        rendered = renderer_class.new(prompt, choices: choices, media: media).render

        @controller.render json: {
          mode: "simulator",
          webhook_processed: true,
          would_send: rendered,
          message_info: {
            to: context["request.user_id"],
            timestamp: Time.now.iso8601
          }
        }

        nil
      end

      def simulate?(context)
        return false unless context["enable_simulator"]

        @body.dig("simulator_mode") &&
          FlowChat::Security.valid_simulator_cookie?(@controller.request.cookies[FlowChat::Security::SIMULATOR_COOKIE_NAME])
      end

      def parse_request_body(request)
        return @body if @body

        @body = if request.body.nil?
          {}
        else
          request.body.rewind if request.body.respond_to?(:rewind)
          JSON.parse(request.body.read)
        end
      end

      def configuration_error_class
        FlowChat::Meta::ConfigurationError
      end

      def log_tag
        self.class.name.split("::").last
      end
    end
  end
end
```

The `should_enqueue_async?` line above is awkward. Write it plainly instead:

```ruby
        if should_enqueue_async?
          enqueue_async_job
          return :enqueued
        end
```

- [ ] **Step 4: Teach the session middleware the two platforms**

In `lib/flow_chat/session/middleware.rb`, change `platform_default_identifier`:

```ruby
      def platform_default_identifier(context)
        platform = context["request.platform"]

        case platform
        when :whatsapp
          :msisdn
        when :messenger, :instagram
          # Neither platform exposes a phone number. The sender id is scoped to
          # the app and the account, and is stable per user.
          :user_id
        else
          :request_id
        end
      end
```

- [ ] **Step 5: Run the tests**

Run: `ruby -Itest test/unit/meta/messaging_gateway_test.rb`
Expected: PASS, 10 tests. `TestGateway` makes this task self-contained, so it must go green here without Task 13.

Run: `bundle exec rake test`
Expected: PASS, 0 failures. The session-middleware change affects every platform, so watch for identifier regressions in the WhatsApp and Telegram suites.

- [ ] **Step 6: Commit**

```bash
git add lib/flow_chat/meta/messaging_gateway.rb lib/flow_chat/session/middleware.rb \
        test/unit/meta/messaging_gateway_test.rb test/support/test_helpers.rb
git commit -m "feat(meta): implement the Messenger Platform envelope once"
```

---

## Task 13: Messenger gateway and choice mapper

**Goal:** The Messenger subclass, and the middleware that maps a reply back to the choice key the flow used.

**Files:**
- Create: `lib/flow_chat/messenger/gateway/send_api.rb`
- Create: `lib/flow_chat/messenger/middleware/choice_mapper.rb`
- Create: `test/unit/messenger/middleware/choice_mapper_test.rb`

**Acceptance Criteria:**
- [ ] `FlowChat::Messenger::Gateway::SendApi` subclasses `FlowChat::Meta::MessagingGateway` and overrides `platform`, `gateway_name`, `configuration_class`, `client_class`, `renderer_class`, `choice_mapper_class`
- [ ] A tapped quick reply resolves to the flow's original choice key
- [ ] On the numbered rung, typing `"3"` resolves to the third choice's key
- [ ] Ids resolve before positions, so a choice labelled `"1"` is not shadowed by position `"1"`
- [ ] The position map is absent on the quick-reply and carousel rungs

**Verify:** `ruby -Itest test/unit/messenger/middleware/choice_mapper_test.rb && ruby -Itest test/unit/meta/messaging_gateway_test.rb` → PASS

**Steps:**

- [ ] **Step 1: Write the failing choice-mapper test**

Create `test/unit/messenger/middleware/choice_mapper_test.rb`:

```ruby
require "test_helper"

class MessengerChoiceMapperTest < Minitest::Test
  def build(app)
    FlowChat::Messenger::Middleware::ChoiceMapper.new(app)
  end

  def context_with(input, session: nil)
    context = FlowChat::Context.new
    context.input = input
    context["session.id"] = "session_1"
    context.session = session || FlowChat::TestSupport::MockSessionStore.new
    context
  end

  def test_tapped_quick_reply_resolves_to_the_original_key
    choices = {"create" => "Create Account", "login" => "Log In"}
    mapper = build(->(_ctx) { [:prompt, "Pick", choices, nil] })

    first = context_with("")
    _, _, transformed, _ = mapper.call(first)

    tapped = transformed.keys.first
    second = context_with(tapped, session: first.session)
    mapper.call(second)

    assert_equal "create", second.input
  end

  def test_typed_number_resolves_on_the_numbered_rung
    choices = (1..31).to_h { |i| ["k#{i}", "Option #{i}"] }
    mapper = build(->(_ctx) { [:prompt, "Pick", choices, nil] })

    first = context_with("")
    mapper.call(first)

    second = context_with("3", session: first.session)
    mapper.call(second)

    assert_equal "k3", second.input
  end

  # A generated id and a position occupy the same key space: normalize_label
  # keeps digits, so a choice labelled "1" generates the id "1".
  def test_generated_ids_win_over_positions
    choices = {"a" => "2", "b" => "1"}
    mapper = build(->(_ctx) { [:prompt, "Pick", choices, nil] })

    first = context_with("")
    mapper.call(first)

    second = context_with("1", session: first.session)
    mapper.call(second)

    assert_equal "b", second.input, "the id for the label \"1\" must win over position 1"
  end

  def test_no_position_map_on_the_quick_reply_rung
    choices = {"a" => "Alpha", "b" => "Beta"}
    mapper = build(->(_ctx) { [:prompt, "Pick", choices, nil] })

    context = context_with("")
    mapper.call(context)

    assert_nil context.session.get("messenger.position_mapping")
  end
end
```

Use whatever session double the existing `test/unit/whatsapp/middleware/choice_mapper_test.rb` uses rather than assuming `MockSessionStore`.

- [ ] **Step 2: Run and watch it fail**

Run: `ruby -Itest test/unit/messenger/middleware/choice_mapper_test.rb`
Expected: FAIL with `NameError: uninitialized constant FlowChat::Messenger::Middleware`.

- [ ] **Step 3: Write the gateway subclass**

Create `lib/flow_chat/messenger/gateway/send_api.rb`:

```ruby
module FlowChat
  module Messenger
    module Gateway
      # Facebook Messenger, on the shared Messenger Platform envelope.
      class SendApi < FlowChat::Meta::MessagingGateway
        def platform
          :messenger
        end

        def gateway_name
          :messenger_send_api
        end

        def configuration_class
          FlowChat::Messenger::Configuration
        end

        def client_class
          FlowChat::Messenger::Client
        end

        def renderer_class
          FlowChat::Messenger::Renderer
        end

        def self.choice_mapper_class
          FlowChat::Messenger::Middleware::ChoiceMapper
        end

        private

        def configuration_error_class
          FlowChat::Messenger::ConfigurationError
        end

        def platform_label
          "Messenger"
        end
      end
    end
  end
end
```

- [ ] **Step 4: Write the choice mapper**

Create `lib/flow_chat/messenger/middleware/choice_mapper.rb`:

```ruby
module FlowChat
  module Messenger
    module Middleware
      # Maps a reply back to the choice key the flow used.
      #
      # Two key spaces can be live at once. A tap sends the payload id the
      # renderer put on the button, and on the numbered rung a typed digit sends
      # a position. They are stored separately and resolved ids first, because
      # the spaces overlap: IdGenerator keeps digits, so a choice labelled "1"
      # generates the id "1", which is not necessarily the first choice.
      class ChoiceMapper
        ID_KEY = "messenger.choice_mapping"
        POSITION_KEY = "messenger.position_mapping"

        def initialize(app)
          @app = app
        end

        def call(context)
          @context = context
          @session = context.session

          handle_choice_input if intercept?

          type, prompt, choices, media = @app.call(context)

          choices = create_mappings(choices) if choices.present?

          [type, prompt, choices, media]
        end

        private

        def platform_limits
          FlowChat::Config.messenger
        end

        def always_number?
          false
        end

        def id_key
          self.class::ID_KEY
        end

        def position_key
          self.class::POSITION_KEY
        end

        def resolved_choice
          input = @context.input.to_s
          return nil if input.empty?

          (@session.get(id_key) || {})[input] || (@session.get(position_key) || {})[input]
        end

        def intercept?
          @context.input.present? && resolved_choice.present?
        end

        def handle_choice_input
          original = resolved_choice
          FlowChat.logger.info { "#{self.class.name}: Resolving input #{@context.input} to #{original}" }
          @context.input = original
        end

        def create_mappings(choices)
          generator = FlowChat::IdGenerator.new(max_length: 1000)
          id_choices = {}
          id_mapping = {}

          choices.each do |key, label|
            generated_id = generator.generate_id(label.to_s)
            id_choices[generated_id] = label
            id_mapping[generated_id] = key.to_s
          end

          @session.set(id_key, id_mapping)

          if FlowChat::Meta::ChoiceLadder.numbers_in_body?(choices.length, platform_limits, always_number: always_number?)
            @session.set(position_key, choices.keys.map.with_index(1) { |key, i| [i.to_s, key.to_s] }.to_h)
          else
            @session.delete(position_key)
          end

          id_choices
        end
      end
    end
  end
end
```

- [ ] **Step 5: Run the tests**

Run: `ruby -Itest test/unit/messenger/middleware/choice_mapper_test.rb`
Expected: PASS, 4 tests.

Run: `ruby -Itest test/unit/meta/messaging_gateway_test.rb`
Expected: PASS, 10 tests, still green. Leave `TestGateway` in place: it keeps the base class covered independently of either real platform.

Add one test to `test/unit/messenger/middleware/choice_mapper_test.rb` proving the subclass wires the hooks, since `TestGateway` cannot prove that:

```ruby
  def test_gateway_exposes_the_messenger_hooks
    config = FlowChat::Messenger::Configuration.new(nil)
    config.page_id = "page_1"
    config.access_token = "tok"
    config.verify_token = "verify"

    gateway = FlowChat::Messenger::Gateway::SendApi.new(proc {}, config)

    assert_equal :messenger, gateway.platform
    assert_equal :messenger_send_api, gateway.gateway_name
    assert_equal FlowChat::Messenger::Renderer, gateway.renderer_class
    assert_equal FlowChat::Messenger::Middleware::ChoiceMapper,
      FlowChat::Messenger::Gateway::SendApi.choice_mapper_class
  end
```

- [ ] **Step 6: Run the full suite**

Run: `bundle exec rake test`
Expected: PASS, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add lib/flow_chat/messenger/gateway/send_api.rb lib/flow_chat/messenger/middleware/choice_mapper.rb \
        test/unit/messenger/middleware/choice_mapper_test.rb test/unit/meta/messaging_gateway_test.rb
git commit -m "feat(messenger): wire the gateway and resolve tapped and typed replies"
```

---

## Task 14: Messenger integration test

**Goal:** A full webhook-to-send cycle through a real flow, session store and middleware stack.

**Files:**
- Create: `test/integration/messenger_integration_test.rb`

**Acceptance Criteria:**
- [ ] A first webhook starts a flow and sends the first prompt
- [ ] A tapped quick reply on the second webhook advances the flow, with session state carried
- [ ] A terminal screen sends the final message
- [ ] Async mode enqueues instead of sending, and returns 200

**Verify:** `ruby -Itest test/integration/messenger_integration_test.rb` → PASS

**Steps:**

- [ ] **Step 1: Read the model first**

Read `test/integration/whatsapp_integration_test.rb` in full. Copy its structure: processor construction, session store, flow definition, and how it asserts on sends. Do not invent a new harness.

- [ ] **Step 2: Write the test**

Create `test/integration/messenger_integration_test.rb` with a two-screen flow:

```ruby
require "test_helper"

class MessengerIntegrationTest < Minitest::Test
  class RegistrationFlow < FlowChat::Flow
    def main_page
      name = app.screen(:name) { |prompt| prompt.ask "What is your name?" }
      plan = app.screen(:plan) do |prompt|
        prompt.select "Choose a plan", {"basic" => "Basic", "pro" => "Pro"}
      end
      app.say "Thanks #{name}, you chose #{plan}."
    end
  end

  def setup
    @config = FlowChat::Messenger::Configuration.new(nil)
    @config.page_id = "page_1"
    @config.access_token = "tok"
    @config.verify_token = "verify"
    @config.skip_signature_validation = true

    @sent = []
    FlowChat::Config.cache = FlowChat::TestSupport::MockCache.new
  end

  def test_full_conversation
    first = run_webhook(text: "Hello")
    assert_match(/What is your name/, last_sent_prompt)

    run_webhook(text: "Ama")
    assert_match(/Choose a plan/, last_sent_prompt)

    tapped = last_sent_choices.keys.first
    run_webhook(quick_reply: tapped)
    assert_match(/Thanks Ama/, last_sent_prompt)
  end
end
```

The three helpers, in full. `send_message` is replaced with a recorder rather than stubbed over HTTP, because what this test asserts is the prompt and choices the flow produced, not the wire format (Task 11 covers that):

```ruby
  private

  def processor_for(controller)
    FlowChat::Processor.new(controller) do |config|
      config.use_gateway FlowChat::Messenger::Gateway::SendApi, @config
      config.use_session_store FlowChat::Session::CacheSessionStore
    end
  end

  # Replaces the client's send with a recorder. The gateway builds its client in
  # the constructor, so this reaches in after the processor is built.
  def record_sends(gateway)
    sent = @sent
    gateway.client.define_singleton_method(:send_message) do |to, prompt, choices: nil, media: nil|
      sent << {to: to, prompt: prompt, choices: choices, media: media}
      {"recipient_id" => to, "message_id" => "mid.#{sent.length}"}
    end
  end

  def run_webhook(text: nil, quick_reply: nil)
    message = {"mid" => "mid.in.#{@sent.length}"}
    if quick_reply
      message["text"] = "tapped"
      message["quick_reply"] = {"payload" => quick_reply}
    else
      message["text"] = text
    end

    run_raw_webhook({
      "object" => "page",
      "entry" => [{
        "id" => "page_1",
        "messaging" => [{
          "sender" => {"id" => "psid_1"},
          "recipient" => {"id" => "page_1"},
          "timestamp" => 1_700_000_000,
          "message" => message
        }]
      }]
    })
  end

  def run_raw_webhook(body)
    context = build_messaging_context(body)
    processor = processor_for(context.controller)
    record_sends(processor.gateway)
    processor.run(RegistrationFlow, :main_page)
    context
  end

  def last_sent_prompt
    @sent.last[:prompt]
  end

  def last_sent_choices
    @sent.last[:choices]
  end
```

`processor.gateway` may not be exposed. Check `lib/flow_chat/processor.rb` first: if the built gateway is not reachable from the processor, record sends by stubbing `FlowChat::Messenger::Client#send_message` on the class for the duration of the test instead, and note which approach you used.

- [ ] **Step 3: Run it**

Run: `ruby -Itest test/integration/messenger_integration_test.rb`
Expected: PASS.

- [ ] **Step 4: Add the async case**

Add a test that builds the processor with `config.use_async(factory: :messenger)`, registers that factory, and asserts the webhook enqueues rather than sending. Follow `test/integration/async_flow_execution_test.rb` for the job double.

Run: `ruby -Itest test/integration/messenger_integration_test.rb`
Expected: PASS.

- [ ] **Step 5: Run the full suite**

Run: `bundle exec rake test`
Expected: PASS, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add test/integration/messenger_integration_test.rb test/support/test_helpers.rb
git commit -m "test(messenger): drive a conversation end to end"
```

---

# Phase 3: Instagram

## Task 15: Instagram configuration

**Goal:** Instagram credentials on the Facebook Login path, with Instagram's own limits.

**Files:**
- Create: `lib/flow_chat/instagram/configuration.rb`
- Create: `test/unit/instagram/configuration_test.rb`
- Modify: `lib/flow_chat/config.rb` (add `Config.instagram`)

**Acceptance Criteria:**
- [ ] `FlowChat::Instagram::Configuration` carries `page_id`, `instagram_account_id`, `access_token`, `verify_token`, `app_id`, `app_secret`, `skip_signature_validation`
- [ ] `from_credentials` reads `instagram:` credentials with `INSTAGRAM_*` env fallback
- [ ] `valid?` requires `access_token`, `page_id` and `verify_token`
- [ ] `FlowChat::Config.instagram.max_text_length` is 1000
- [ ] `account_id` returns `page_id`, since the Facebook Login path keys webhooks on the linked page

**Verify:** `ruby -Itest test/unit/instagram/configuration_test.rb` → PASS

**Steps:**

- [ ] **Step 1: Write the failing test**

Create `test/unit/instagram/configuration_test.rb` following the shape of `test/unit/messenger/configuration_test.rb`, asserting:

```ruby
  def test_limits_are_instagram_specific
    assert_equal 1000, FlowChat::Config.instagram.max_text_length
    assert_equal 13, FlowChat::Config.instagram.max_quick_replies
    assert_equal 10, FlowChat::Config.instagram.max_carousel_elements
  end

  def test_account_id_is_the_linked_page
    config = FlowChat::Instagram::Configuration.new(nil)
    config.page_id = "page_1"
    config.instagram_account_id = "ig_1"

    assert_equal "page_1", config.account_id
  end
```

- [ ] **Step 2: Run and watch it fail**

Run: `ruby -Itest test/unit/instagram/configuration_test.rb`
Expected: FAIL with `NameError: uninitialized constant FlowChat::Instagram`.

- [ ] **Step 3: Add the global config object**

In `lib/flow_chat/config.rb`:

```ruby
    # Instagram-specific configuration object
    def self.instagram
      @instagram ||= InstagramConfig.new
    end
```

```ruby
    class InstagramConfig
      attr_reader :api_base_url, :max_text_length, :max_quick_replies,
        :max_carousel_elements, :max_buttons_per_element,
        :max_quick_reply_title, :max_button_title, :max_element_title

      def initialize
        @api_base_url = "https://graph.facebook.com/v23.0"
        # Meta: "Message text must be UTF-8 and be 1,000 bytes or less."
        @max_text_length = 1000
        @max_quick_replies = 13
        @max_quick_reply_title = 20
        @max_carousel_elements = 10
        @max_buttons_per_element = 3
        @max_button_title = 20
        @max_element_title = 80
      end
    end
```

- [ ] **Step 4: Write the configuration class**

Create `lib/flow_chat/instagram/configuration.rb`, mirroring `lib/flow_chat/messenger/configuration.rb` with these differences: an extra `instagram_account_id` accessor, `INSTAGRAM_*` env keys, `Rails.application.credentials.instagram`, `api_base_url` from `FlowChat::Config.instagram`, and an `Instagram::ConfigurationError`. `account_id` returns `page_id`.

```ruby
module FlowChat
  module Instagram
    class ConfigurationError < StandardError; end

    class Configuration
      include FlowChat::NamedConfiguration

      attr_accessor :access_token, :page_id, :instagram_account_id, :verify_token,
        :app_id, :app_secret, :name, :skip_signature_validation

      def initialize(name)
        @name = name
        @skip_signature_validation = false

        FlowChat.logger.debug { "Instagram::Configuration: Initialized configuration with name: #{name || "anonymous"}" }

        register_as(name) if name.present?
      end

      def self.from_credentials
        config = new(nil)

        if defined?(Rails) && Rails.respond_to?(:application) && Rails.application&.credentials&.instagram
          credentials = Rails.application.credentials.instagram
          config.access_token = credentials[:access_token]
          config.page_id = credentials[:page_id]
          config.instagram_account_id = credentials[:instagram_account_id]
          config.verify_token = credentials[:verify_token]
          config.app_id = credentials[:app_id]
          config.app_secret = credentials[:app_secret]
          config.skip_signature_validation = credentials[:skip_signature_validation] || false
        else
          config.access_token = ENV["INSTAGRAM_ACCESS_TOKEN"]
          config.page_id = ENV["INSTAGRAM_PAGE_ID"]
          config.instagram_account_id = ENV["INSTAGRAM_ACCOUNT_ID"]
          config.verify_token = ENV["INSTAGRAM_VERIFY_TOKEN"]
          config.app_id = ENV["INSTAGRAM_APP_ID"]
          config.app_secret = ENV["INSTAGRAM_APP_SECRET"]
          config.skip_signature_validation = ENV["INSTAGRAM_SKIP_SIGNATURE_VALIDATION"] == "true"
        end

        config
      end

      def valid?
        access_token.present? && page_id.present? && verify_token.present?
      end

      # On the Facebook Login path the webhook entry is keyed on the linked page,
      # not the Instagram account, so that is what an inbound event is checked
      # against.
      def account_id
        page_id
      end

      def messages_url
        "#{api_base_url}/#{page_id}/messages"
      end

      def attachment_upload_url
        "#{api_base_url}/#{page_id}/message_attachments"
      end

      def api_base_url
        FlowChat::Config.instagram.api_base_url
      end

      def api_headers
        {
          "Authorization" => "Bearer #{access_token}",
          "Content-Type" => "application/json"
        }
      end
    end
  end
end
```

- [ ] **Step 5: Run the test**

Run: `ruby -Itest test/unit/instagram/configuration_test.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/flow_chat/instagram/configuration.rb lib/flow_chat/config.rb test/unit/instagram/configuration_test.rb
git commit -m "feat(instagram): configure the account a gateway speaks for"
```

---

## Task 16: Instagram renderer, client, gateway and choice mapper

**Goal:** The Instagram platform, differing from Messenger in three ways: the body is always numbered, text is measured in bytes, and the limits come from `Config.instagram`.

**Files:**
- Create: `lib/flow_chat/instagram/renderer.rb`
- Create: `lib/flow_chat/instagram/client.rb`
- Create: `lib/flow_chat/instagram/gateway/send_api.rb`
- Create: `lib/flow_chat/instagram/middleware/choice_mapper.rb`
- Create: `test/unit/instagram/renderer_test.rb`
- Create: `test/unit/instagram/client_test.rb`

**Acceptance Criteria:**
- [ ] Quick replies and carousels both also carry a numbered list in the body
- [ ] A screen with no choices has no numbered list
- [ ] Text is split by **bytes**, not characters: a 1000-byte cap with multibyte characters produces more chunks than a naive character count would
- [ ] The choice mapper always stores the position map, so a typed number works at every rung
- [ ] `Instagram::Gateway::SendApi` subclasses `Meta::MessagingGateway` directly, not `Messenger::Gateway::SendApi`

**Verify:** `ruby -Itest test/unit/instagram/renderer_test.rb && ruby -Itest test/unit/instagram/client_test.rb` → PASS

**Steps:**

- [ ] **Step 1: Write the failing renderer test**

Create `test/unit/instagram/renderer_test.rb`:

```ruby
require "test_helper"

class InstagramRendererTest < Minitest::Test
  def render(message, choices: nil, media: nil)
    FlowChat::Instagram::Renderer.new(message, choices: choices, media: media).render
  end

  # Quick replies and carousels render on mobile only. Without numbers in the
  # body a user on desktop gets a prompt with no way to answer it.
  def test_quick_replies_also_number_the_body
    result = render("Pick one", choices: {"a" => "Alpha", "b" => "Beta"})

    assert_equal :quick_replies, result[0]
    assert_includes result[1], "1. Alpha"
    assert_includes result[1], "2. Beta"
  end

  def test_carousel_also_numbers_the_body
    choices = (1..14).to_h { |i| ["k#{i}", "Option #{i}"] }

    result = render("Pick one", choices: choices)

    assert_equal :carousel, result[0]
    assert_includes result[1], "14. Option 14"
  end

  def test_no_choices_means_no_numbers
    result = render("Just a message")

    assert_equal "Just a message", result[1]
  end
end
```

- [ ] **Step 2: Run and watch it fail**

Run: `ruby -Itest test/unit/instagram/renderer_test.rb`
Expected: FAIL with `NameError: uninitialized constant FlowChat::Instagram::Renderer`.

- [ ] **Step 3: Write the renderer**

Create `lib/flow_chat/instagram/renderer.rb`. It is `Messenger::Renderer` with two hooks flipped:

```ruby
module FlowChat
  module Instagram
    class Renderer < FlowChat::Messenger::Renderer
      private

      def limits
        FlowChat::Config.instagram
      end

      # Quick replies and carousels are mobile only on Instagram, so the options
      # are always listed in the body as well. A user on desktop sees the prompt
      # and nothing tappable, and without the list has no way to reply.
      def always_number?
        true
      end
    end
  end
end
```

This is the one place Instagram inherits from Messenger, and it is deliberate: the renderers really are the same algorithm with different constants. The gateways are not, which is why they are siblings.

- [ ] **Step 4: Write the failing client test**

Create `test/unit/instagram/client_test.rb`, mirroring `test/unit/messenger/client_test.rb`, plus the byte-splitting case:

```ruby
  # Meta measures Instagram text in bytes, not characters.
  def test_text_is_split_by_bytes
    # Each "é" is 2 bytes, so 600 of them is 1200 bytes: over the 1000 cap
    # even though the character count is not.
    text = (["é" * 60] * 10).join(" ")
    assert_operator text.length, :<, 1000
    assert_operator text.bytesize, :>, 1000

    @client.send_message("igsid_1", text)

    assert_requested(:post, @config.messages_url, times: 2)
  end
```

- [ ] **Step 5: Write the client**

Create `lib/flow_chat/instagram/client.rb`:

```ruby
module FlowChat
  module Instagram
    class Client < FlowChat::Messenger::Client
      private

      def renderer_class
        FlowChat::Instagram::Renderer
      end

      def platform
        :instagram
      end

      def limits
        FlowChat::Config.instagram
      end

      # Meta: "Message text must be UTF-8 and be 1,000 bytes or less." A
      # character count would let multibyte text through and be rejected.
      def measure(string)
        string.bytesize
      end
    end
  end
end
```

- [ ] **Step 6: Write the gateway and choice mapper**

Create `lib/flow_chat/instagram/gateway/send_api.rb`:

```ruby
module FlowChat
  module Instagram
    module Gateway
      # Instagram DMs, on the shared Messenger Platform envelope.
      #
      # A sibling of the Messenger gateway rather than a subclass of it: the two
      # differ in credentials, limits and subscription object, and neither owns
      # the other.
      class SendApi < FlowChat::Meta::MessagingGateway
        def platform
          :instagram
        end

        def gateway_name
          :instagram_send_api
        end

        def configuration_class
          FlowChat::Instagram::Configuration
        end

        def client_class
          FlowChat::Instagram::Client
        end

        def renderer_class
          FlowChat::Instagram::Renderer
        end

        def self.choice_mapper_class
          FlowChat::Instagram::Middleware::ChoiceMapper
        end

        # Confirm against the Meta app dashboard before relying on this. On the
        # Facebook Login path Meta's own docs were ambiguous about whether these
        # arrive under "page" or "instagram", which is why it is a hook.
        def expected_webhook_object
          "instagram"
        end

        private

        def configuration_error_class
          FlowChat::Instagram::ConfigurationError
        end

        def platform_label
          "Instagram"
        end
      end
    end
  end
end
```

Create `lib/flow_chat/instagram/middleware/choice_mapper.rb`:

```ruby
module FlowChat
  module Instagram
    module Middleware
      class ChoiceMapper < FlowChat::Messenger::Middleware::ChoiceMapper
        ID_KEY = "instagram.choice_mapping"
        POSITION_KEY = "instagram.position_mapping"

        private

        def platform_limits
          FlowChat::Config.instagram
        end

        # The body always carries numbers here, so a typed number must always
        # resolve.
        def always_number?
          true
        end
      end
    end
  end
end
```

- [ ] **Step 7: Run the tests**

Run: `ruby -Itest test/unit/instagram/renderer_test.rb && ruby -Itest test/unit/instagram/client_test.rb`
Expected: PASS.

- [ ] **Step 8: Run the full suite**

Run: `bundle exec rake test`
Expected: PASS, 0 failures.

- [ ] **Step 9: Commit**

```bash
git add lib/flow_chat/instagram/ test/unit/instagram/
git commit -m "feat(instagram): add the gateway, numbering options for desktop

Quick replies and carousels render on mobile Instagram only, so the
renderer lists the options numbered in the body at every rung and the
choice mapper always keeps the positions. Without that a user on a
browser sees a prompt with nothing tappable and no way to answer.

Text is measured in bytes, since Meta caps Instagram messages at 1,000
bytes rather than 1,000 characters."
```

---

## Task 17: Instagram integration test

**Goal:** A full webhook-to-send cycle on Instagram, including a typed-number reply.

**Files:**
- Create: `test/integration/instagram_integration_test.rb`

**Acceptance Criteria:**
- [ ] A conversation advances via a tapped quick reply
- [ ] The same conversation advances via a typed number, proving the desktop path works
- [ ] A webhook whose `object` does not match `expected_webhook_object` is ignored with 200

**Verify:** `ruby -Itest test/integration/instagram_integration_test.rb` → PASS

**Steps:**

- [ ] **Step 1: Write the test**

Create `test/integration/instagram_integration_test.rb`, modelled on `test/integration/messenger_integration_test.rb` from Task 14, with the two reply styles:

```ruby
  def test_typed_number_advances_the_flow
    run_webhook(text: "Hello")
    assert_match(/What is your name/, last_sent_prompt)

    run_webhook(text: "Ama")
    assert_match(/Choose a plan/, last_sent_prompt)
    assert_match(/1\. Basic/, last_sent_prompt)

    run_webhook(text: "2")
    assert_match(/you chose pro/, last_sent_prompt)
  end

  def test_webhook_for_another_object_is_ignored
    context = run_raw_webhook({"object" => "page", "entry" => []})

    assert_equal :ok, context.controller.last_head_status
  end
```

- [ ] **Step 2: Run it**

Run: `ruby -Itest test/integration/instagram_integration_test.rb`
Expected: PASS.

- [ ] **Step 3: Run the full suite**

Run: `bundle exec rake test`
Expected: PASS, 0 failures.

- [ ] **Step 4: Commit**

```bash
git add test/integration/instagram_integration_test.rb
git commit -m "test(instagram): drive a conversation by tap and by typed number"
```

---

## Task 18: Simulator support

**Goal:** Both platforms selectable in the built-in simulator.

**Note on scope:** the simulator is not extensible by configuration alone. `lib/flow_chat/simulator/controller.rb:29-70` holds a `configurations` hash, which is the easy part, but `lib/flow_chat/simulator/views/simulator.html.erb` branches on `processor_type` in embedded JavaScript at six points (lines 1109, 1129-1136, 1187-1191, 1212-1214, 1221-1225) and carries per-platform screen chrome (`#whatsapp-screen`, line 941). Both new platforms render as chat bubbles exactly like WhatsApp, so they reuse the WhatsApp screen chrome rather than growing two more copies of it.

**Files:**
- Modify: `lib/flow_chat/simulator/controller.rb:29-70`
- Modify: `lib/flow_chat/simulator/views/simulator.html.erb` (the six `processor_type` branches and the screen selector)

**Acceptance Criteria:**
- [ ] Messenger and Instagram appear in the simulator's platform selector
- [ ] Both post the `entry[].messaging[]` body shape their gateway parses, with `simulator_mode: true`
- [ ] Both render in the chat-bubble screen, not the USSD screen
- [ ] A simulated send returns the rendered payload as JSON rather than calling the Send API
- [ ] The signed-cookie gate still applies: no valid cookie means no simulator mode

**Verify:** `bundle exec rake test` → PASS, and loading the simulator page shows five platforms

**Steps:**

- [ ] **Step 1: Add the two configurations**

In `lib/flow_chat/simulator/controller.rb`, add to the `configurations` hash after the `whatsapp` entry:

```ruby
          messenger: {
            name: "Messenger (Send API)",
            description: "Facebook Messenger integration using the Send API",
            processor_type: "messenger",
            gateway: "send_api",
            endpoint: "/messenger/webhook",
            icon: "💬",
            color: "#0084FF",
            settings: {
              user_id: default_phone_number,
              contact_name: default_contact_name
            }
          },
          instagram: {
            name: "Instagram (Send API)",
            description: "Instagram DM integration using the Send API",
            processor_type: "instagram",
            gateway: "send_api",
            endpoint: "/instagram/webhook",
            icon: "📷",
            color: "#E1306C",
            settings: {
              user_id: default_phone_number,
              contact_name: default_contact_name
            }
          },
```

- [ ] **Step 2: Introduce one predicate instead of six string comparisons**

In `simulator.html.erb`, the JS asks `processor_type === 'whatsapp'` in six places to mean "this platform is a chat bubble UI". Replace those comparisons with a single helper defined next to the other state helpers, so adding a sixth platform later is one edit rather than six:

```javascript
      const CHAT_PLATFORMS = ['whatsapp', 'messenger', 'instagram']

      function isChatPlatform(processorType) {
        return CHAT_PLATFORMS.includes(processorType)
      }
```

Then at each of lines 1109, 1130, 1136, 1189, 1212 and 1223, replace the `=== 'whatsapp'` test with `isChatPlatform(...)`. Read each branch before editing: some build the request body and need the per-platform shape from Step 3, not just the shared predicate.

- [ ] **Step 3: Build the right webhook body per platform**

The body-building branches (around lines 1187-1191 and 1212-1225) must send the Messenger Platform envelope for the two new platforms, not the WhatsApp one:

```javascript
        function buildMessagingBody(processorType, text) {
          return {
            object: processorType === 'instagram' ? 'instagram' : 'page',
            entry: [{
              id: state.currentConfig.settings.page_id || 'page_1',
              messaging: [{
                sender: { id: state.currentConfig.settings.user_id },
                recipient: { id: state.currentConfig.settings.page_id || 'page_1' },
                timestamp: Date.now(),
                message: { mid: 'mid.' + Date.now(), text: text }
              }]
            }],
            simulator_mode: true
          }
        }
```

Wire `messenger` and `instagram` to this builder. If Task 20 changes Instagram's `expected_webhook_object` to `page`, this `object` expression changes with it.

- [ ] **Step 4: Point both at the chat screen**

At line 1136 the screen toggle hides `#whatsapp-screen` unless the platform is WhatsApp. Use `isChatPlatform` so both new platforms show the same bubble screen. Confirm the header label at line 942 reads from config rather than being hardcoded to "WhatsApp"; if it is hardcoded, drive it from `state.currentConfig.name`.

- [ ] **Step 5: Verify the gate still holds**

Confirm `simulate?` in `Meta::MessagingGateway` requires both `context["enable_simulator"]` and a valid cookie. Then confirm no test passes with the cookie removed.

Run: `ruby -Itest test/unit/security_test.rb`
Expected: PASS.

- [ ] **Step 6: Load the page**

Start the simulator however the project normally does (check `docs/testing.md` for the documented route) and confirm five platforms appear, that selecting Messenger shows the bubble screen, and that sending a message returns a JSON `would_send` payload.

- [ ] **Step 7: Run the full suite**

Run: `bundle exec rake test`
Expected: PASS, 0 failures.

- [ ] **Step 8: Commit**

```bash
git add lib/flow_chat/simulator/
git commit -m "feat(simulator): add messenger and instagram

The view asked processor_type === 'whatsapp' in six places to mean \"this
platform draws chat bubbles\". That is now one predicate over a list, so
the two new platforms reuse the bubble screen instead of copying it."
```

---

## Task 19: Documentation

**Goal:** Both platforms documented to the standard of the existing platform guides.

**Files:**
- Create: `docs/platforms/messenger.md`, `docs/platforms/instagram.md`
- Modify: `README.md:26`, `README.md:74`, `README.md:186`, `README.md:236`
- Modify: `docs/gateway-context-variables.md`

**Acceptance Criteria:**
- [ ] Each platform guide covers setup, credentials, webhook fields, the choice ladder with its real numbers, media, echoes and coexistence, and limits
- [ ] The README platform table gains both gateway classes, platform symbols and rendering summaries
- [ ] The README platform-differences table states the real caps: 13 quick replies, 30 via carousel, Instagram mobile only, 1000 bytes
- [ ] `docs/gateway-context-variables.md` lists what both gateways set, including `request.msisdn` being nil
- [ ] No em-dashes anywhere in the new or edited prose

**Verify:** `grep -c "—" docs/platforms/messenger.md docs/platforms/instagram.md` → 0 for both

**Steps:**

- [ ] **Step 1: Read the model**

Read `docs/platforms/whatsapp.md` and `docs/platforms/telegram.md` in full. Match their structure and register: dense plain prose, real limits, documented edge cases, no marketing adjectives.

- [ ] **Step 2: Write the two guides**

Each guide covers, in this order: what the platform is and which Meta product it uses; credentials and where they come from; webhook setup and the fields to subscribe; a wiring example with `use_gateway`; the choice ladder table with real numbers; media in and out; echoes and what `echo_origin` means for coexistence; the 24 hour window and what happens when a send is rejected; and a limits table.

For Instagram, state plainly that quick replies and carousels do not render on desktop, and that this is why the options are always numbered in the body.

- [ ] **Step 3: Update the README**

Add rows to the platform table at `README.md:74`:

| Platform | Gateway class | Platform symbol | Rendering |
|---|---|---|---|
| Messenger | `FlowChat::Messenger::Gateway::SendApi` | `:messenger` | Quick replies, carousel, numbered text |
| Instagram | `FlowChat::Instagram::Gateway::SendApi` | `:instagram` | Quick replies, carousel, always numbered |

Add both to the platform-differences table at `README.md:186`, the intro sentence at `README.md:26`, and the docs index at `README.md:236`.

- [ ] **Step 4: Update the context-variables doc**

Add a column or section for both gateways in `docs/gateway-context-variables.md`, noting `request.msisdn` is nil and `request.user_id` holds the PSID or IGSID.

- [ ] **Step 5: Check the prose**

Run: `grep -n "—" docs/platforms/messenger.md docs/platforms/instagram.md README.md docs/gateway-context-variables.md`
Expected: no output for the new files. Pre-existing em-dashes elsewhere in the README are not this task's business unless they are in a line you edited.

- [ ] **Step 6: Commit**

```bash
git add docs/platforms/messenger.md docs/platforms/instagram.md README.md docs/gateway-context-variables.md
git commit -m "docs: document messenger and instagram"
```

---

## Task 20: Verify the two unresolvable facts with the user

**Goal:** Close the two gaps that cannot be settled from this machine.

**Files:**
- Modify: `lib/flow_chat/instagram/gateway/send_api.rb` (`expected_webhook_object`, if the answer differs)
- Modify: `lib/flow_chat/instagram/renderer.rb` (drop the carousel rung, if it reads badly)

**Acceptance Criteria:**
- [ ] The Instagram `expected_webhook_object` matches what the user's Meta app dashboard actually shows
- [ ] The Instagram carousel decision is confirmed against a real device, or the rung is dropped
- [ ] Any code change from the answers is made and tested

**Verify:** `bundle exec rake test` → PASS after any change

**User Verification Required:**
Before marking this task complete, you MUST call AskUserQuestion:
```yaml
AskUserQuestion:
  question: "Two things I cannot check from here. In your Meta app dashboard, which webhook object are Instagram messaging events subscribed under, and does the Instagram carousel look acceptable for a plain list of options on a real device?"
  header: "Verification"
  options:
    - label: "object is instagram, carousel is fine"
      description: "Keep expected_webhook_object as \"instagram\" and keep the carousel rung between 14 and 30 choices"
    - label: "object is page, carousel is fine"
      description: "Change expected_webhook_object to \"page\" and keep the carousel rung"
    - label: "object is instagram, carousel reads badly"
      description: "Keep the object and drop the carousel rung on Instagram, so above 13 choices goes straight to numbered text"
    - label: "object is page, carousel reads badly"
      description: "Change the object to \"page\" and drop the carousel rung on Instagram"
```

**If the user selects an option indicating rework:** apply the change, re-run the suite, and re-verify with AskUserQuestion again.

**Steps:**

- [ ] **Step 1: Ask**

Call `AskUserQuestion` exactly as above. Do not guess either answer.

- [ ] **Step 2: Apply the webhook object answer**

If the answer is `page`, change `expected_webhook_object` in `lib/flow_chat/instagram/gateway/send_api.rb` to `"page"` and update the comment to record that it was confirmed rather than assumed. Update the Instagram integration test's payloads to match.

- [ ] **Step 3: Apply the carousel answer**

If the carousel reads badly, override the ladder in `lib/flow_chat/instagram/renderer.rb` so `:carousel` is never chosen:

```ruby
      # Confirmed on a real device: the carousel needs a title per card and a
      # plain option list has none, so it reads as noise. Above the quick-reply
      # cap the options go in the body instead.
      def render
        return build_attachment if media && choices.blank?

        rung = FlowChat::Meta::ChoiceLadder.rung_for(choice_count, limits)
        rung = :numbered if rung == :carousel

        case rung
        when :none then build_text
        when :quick_replies then build_quick_replies
        when :numbered then build_numbered
        end
      end
```

Update `test/unit/instagram/renderer_test.rb` to assert the new behavior, replacing `test_carousel_also_numbers_the_body`.

- [ ] **Step 4: Run the full suite**

Run: `bundle exec rake test`
Expected: PASS, 0 failures.

- [ ] **Step 5: Update the spec's open items**

In `docs/superpowers/specs/2026-08-10-messenger-instagram-design.md`, replace the "Open items for implementation" entries 2 and 3 with what was confirmed, so the spec stops claiming they are unknown.

- [ ] **Step 6: Commit**

```bash
git add lib/flow_chat/instagram/ test/ docs/superpowers/specs/2026-08-10-messenger-instagram-design.md
git commit -m "fix(instagram): settle the webhook object and carousel questions"
```

---

## Task 21: Confirm the Messenger text cap and close out

**Goal:** Replace the one assumed constant with a verified one, and confirm the whole branch is green.

**Files:**
- Modify: `lib/flow_chat/config.rb` (`MessengerConfig#max_text_length`, if wrong)
- Modify: `docs/superpowers/specs/2026-08-10-messenger-instagram-design.md` (open item 1)

**Acceptance Criteria:**
- [ ] `max_text_length` for Messenger matches Meta's documented cap, verified rather than assumed
- [ ] The spec's open item 1 is resolved
- [ ] `bundle exec rake test` passes with 0 failures and 0 errors
- [ ] `standardrb` (or whatever linter the Rakefile runs) is clean

**Verify:** `bundle exec rake test` → PASS, 0 failures, 0 errors

**Steps:**

- [ ] **Step 1: Verify the cap**

Fetch Meta's Send API reference for the `message.text` limit. The design assumed 2000 because the reference page would not render during design. If it is different, change `@max_text_length` in `MessengerConfig` and update the client test's long-text fixture so it still crosses the boundary.

- [ ] **Step 2: Update the spec**

Replace open item 1 with the confirmed number and its source.

- [ ] **Step 3: Run everything**

Run: `bundle exec rake test`
Expected: PASS, 0 failures, 0 errors.

Run: `bundle exec rake -T` to find the lint task, then run it.
Expected: clean.

- [ ] **Step 4: Review the whole diff**

Run: `git diff feat/coexistence-webhooks...HEAD --stat`
Confirm nothing unintended was touched, particularly that `lib/flow_chat/whatsapp/id_generator.rb` is gone and the three configuration classes lost their duplicated registries.

- [ ] **Step 5: Commit**

```bash
git add lib/flow_chat/config.rb docs/superpowers/specs/2026-08-10-messenger-instagram-design.md
git commit -m "fix(messenger): use the documented text cap"
```

---

## Spec coverage check

| Spec section | Task |
|---|---|
| Meta shared modules | 1, 2 |
| NamedConfiguration extraction, all five | 3, 8, 15 |
| IdGenerator with configurable cap | 4 |
| `to_plain_text` | 5 |
| WhatsApp fix 1, lists above 10 | 6 |
| WhatsApp fix 2, echo origin | 7 |
| Messenger configuration and `Config.messenger` | 8 |
| Choice ladder | 9 |
| Messenger renderer | 10 |
| Messenger client, delivery hooks, splitting | 11 |
| `Meta::MessagingGateway`, inbound dispatch, echoes, statuses, context, sessions | 12 |
| Messenger gateway and choice mapper | 13 |
| Messenger tests, async | 14 |
| Instagram configuration | 15 |
| Instagram renderer, client, gateway, choice mapper | 16 |
| Instagram tests | 17 |
| Simulator | 18 |
| Docs and README | 19 |
| Open items 2 and 3 | 20 |
| Open item 1 | 21 |

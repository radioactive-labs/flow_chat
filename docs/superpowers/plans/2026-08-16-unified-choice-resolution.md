# Unified Choice Resolution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every choice mapper decide ambiguity under the same equivalence relation its resolver matches on, so a user who types what they see always lands on the choice they read.

**Architecture:** One shared core (`FlowChat::TextTruncator` + `FlowChat::ChoiceTitles`) gains two parameters: a **measure** (characters or bytes) and a **fold** (the normalization the resolver applies before matching). `ambiguity_reason` decides duplication under the fold, and numbers the whole set when two choices collapse under it. The wire value a platform sends back becomes the **displayed title** rather than a separately generated id, which collapses the id map and the alias map into one map and removes `IdGenerator` entirely. USSD is exempt: it resolves on position, which is injective by construction.

**Tech Stack:** Ruby, Minitest, StandardRB.

**User Verification:** NO — no user verification required. Every task is verifiable by the test suite.

---

## Background: the single root cause

Every choice-resolution bug found in review is the same defect — **the ambiguity check and the resolver use different equivalence relations**:

| Mapper | Resolver matches on | Ambiguity checked under | Result |
|---|---|---|---|
| WhatsApp / Messenger / Instagram | `IdGenerator#normalize_label` (punctuation stripped) | raw titles | `{a: "Yes!", b: "Yes"}` → typing `Yes` hits **A** while button **B** reads `Yes` |
| HTTP | `label.strip.downcase` | nothing | `||=` first-wins silently drops the second duplicate |
| Intercom | `label.strip.downcase` | nothing | same first-wins drop |
| Telegram | first 64 **characters** of the key, against a 64-**byte** field | nothing | multibyte key overflows and is rejected; shared prefixes collide and the choice becomes unselectable |
| USSD | position | positions are unique by construction | **no bug** |

USSD is safe because its equivalence relation *is* its uniqueness guarantee. That is the invariant to hold the others to.

**Why numbering is the universal disambiguator:** a position prefix puts the distinguishing token at the *front*, so it survives truncation from the right — including Telegram's 64-byte cut. A hash *suffix* is the one disambiguator a truncating platform can slice off.

### Platform constraints (verified against vendor docs)

| Platform | Field | Limit | Character restrictions |
|---|---|---|---|
| WhatsApp | button reply `id` | 256 chars | none documented |
| WhatsApp | list row `id` | **200 chars** | none documented |
| Messenger / Instagram | quick reply `payload` | 1000 chars | none documented |
| Telegram | `callback_data` | 1–64 **bytes** | none — typed as `bytes` |

No platform restricts the character set. `IdGenerator#normalize_label`'s strip is therefore unjustified, and it is the direct cause of the Meta bug. WhatsApp additionally documents button `title` as *"Must be unique if using multiple buttons"* — the uniqueness `ChoiceTitles.build` guarantees is a platform requirement, not just our convention.

Sources: [WhatsApp reply buttons](https://developers.facebook.com/docs/whatsapp/cloud-api/messages/interactive-reply-buttons-messages/), [WhatsApp lists](https://developers.facebook.com/docs/whatsapp/cloud-api/messages/interactive-list-messages/), [Messenger quick replies](https://developers.facebook.com/docs/messenger-platform/send-messages/quick-replies/), [Telegram bot buttons](https://core.telegram.org/api/bots/buttons).

### File structure

| File | Responsibility after this plan |
|---|---|
| `lib/flow_chat/text_truncator.rb` | Truncate and number a string under a **measure** (characters or bytes) |
| `lib/flow_chat/choice_titles.rb` | Decide ambiguity under a **fold**, and produce distinct displayed titles |
| `lib/flow_chat/id_generator.rb` | **Deleted** |
| `lib/flow_chat/whatsapp/middleware/choice_mapper.rb` | Title-as-wire-value, two maps (title, position) |
| `lib/flow_chat/messenger/middleware/choice_mapper.rb` | Same; Instagram inherits |
| `lib/flow_chat/http/middleware/choice_mapper.rb` | Adopts fold + numbering |
| `lib/flow_chat/intercom/middleware/choice_mapper.rb` | Adopts fold + numbering |
| `lib/flow_chat/telegram/middleware/choice_mapper.rb` | Adopts core with byte measure; gains real maps |
| `lib/flow_chat/ussd/middleware/choice_mapper.rb` | Unchanged — exemption pinned by a test |

---

### Task 1: Give TextTruncator a pluggable measure

**Goal:** `TextTruncator` can cut to a byte budget on character boundaries, so Telegram's 64-byte field is expressible without a Telegram-specific branch.

**Files:**
- Modify: `lib/flow_chat/text_truncator.rb:20-42`
- Test: `test/unit/text_truncator_test.rb`

**Acceptance Criteria:**
- [ ] `truncate(text, cap, measure: :bytes)` never returns a string whose `bytesize` exceeds `cap`
- [ ] Byte truncation never splits a multi-byte character (result is always valid UTF-8)
- [ ] The `"..."` ellipsis is charged in the active measure
- [ ] `number(text, position, cap, measure:)` charges the `"N. "` prefix in the active measure
- [ ] Default measure stays `:characters`; every existing call site is unchanged in behaviour

**Verify:** `bundle exec ruby -Itest test/unit/text_truncator_test.rb` → 0 failures

**Steps:**

- [ ] **Step 1: Write the failing tests**

```ruby
# test/unit/text_truncator_test.rb — append inside the existing class
def test_byte_measure_never_exceeds_the_cap
  text = "日本語のテキストです"  # 3 bytes per character
  result = FlowChat::TextTruncator.truncate(text, 12, measure: :bytes)

  assert_operator result.bytesize, :<=, 12
  assert result.valid_encoding?, "byte truncation must not split a character"
end

def test_byte_measure_leaves_short_multibyte_text_alone
  assert_equal "日本", FlowChat::TextTruncator.truncate("日本", 6, measure: :bytes)
end

def test_character_measure_is_the_default_and_unchanged
  assert_equal "abc...", FlowChat::TextTruncator.truncate("abcdefghij", 6)
end

def test_number_charges_the_prefix_in_bytes
  result = FlowChat::TextTruncator.number("日本語のテキスト", 1, 12, measure: :bytes)

  assert result.start_with?("1. ")
  assert_operator result.bytesize, :<=, 12
  assert result.valid_encoding?
end
```

- [ ] **Step 2: Run to verify they fail**

Run: `bundle exec ruby -Itest test/unit/text_truncator_test.rb`
Expected: FAIL — `unknown keyword: :measure`

- [ ] **Step 3: Implement the measure**

```ruby
# lib/flow_chat/text_truncator.rb — replace .truncate and .number
    ELLIPSIS = "..."

    # Truncates text to a cap expressed in `measure` units.
    #
    # :bytes exists because Meta and Telegram both size their fields in
    # bytes, not characters - FlowChat::Instagram::Client#measure already
    # makes the same distinction for message bodies, with the same reason:
    # a character count lets multibyte text through to be rejected.
    #
    # Byte truncation walks characters rather than slicing bytes, because
    # byteslice can cut a multi-byte sequence in half and produce a string
    # that is no longer valid UTF-8.
    def self.truncate(text, length, measure: :characters)
      text = text.to_s
      length = 0 if length.negative?
      return text if size_of(text, measure) <= length
      return cut(text, length, measure) if length < size_of(ELLIPSIS, measure)

      cut(text, length - size_of(ELLIPSIS, measure), measure) + ELLIPSIS
    end

    def self.number(text, position, cap, measure: :characters)
      prefix = "#{position}. "
      prefix + truncate(text.to_s, cap - size_of(prefix, measure), measure: measure)
    end

    def self.size_of(string, measure)
      (measure == :bytes) ? string.bytesize : string.length
    end
    private_class_method :size_of

    # Takes whole characters while they still fit the budget, so the result
    # is always valid UTF-8 whichever measure is in force.
    def self.cut(string, budget, measure)
      return "" if budget <= 0
      return string[0, budget] if measure != :bytes

      taken = +""
      string.each_char do |char|
        break if taken.bytesize + char.bytesize > budget
        taken << char
      end
      taken
    end
    private_class_method :cut
```

- [ ] **Step 4: Run the tests**

Run: `bundle exec ruby -Itest test/unit/text_truncator_test.rb`
Expected: PASS

- [ ] **Step 5: Run the full suite to prove no call site changed behaviour**

Run: `bundle exec rake test`
Expected: 0 failures

- [ ] **Step 6: Commit**

```bash
git add lib/flow_chat/text_truncator.rb test/unit/text_truncator_test.rb
git commit -m "feat(truncator): size text in bytes where a platform does"
```

---

### Task 2: Make ChoiceTitles decide ambiguity under the resolver's fold

**Goal:** `ambiguity_reason` treats two titles as duplicates when they collapse under the fold the resolver will later match on, so numbering fires exactly when the resolver would otherwise be unable to tell two choices apart.

**Files:**
- Modify: `lib/flow_chat/choice_titles.rb:38-113`
- Test: `test/unit/choice_titles_test.rb`

**Acceptance Criteria:**
- [ ] `build`, `ambiguous?` and `ambiguity_reason` accept `fold:` (default identity) and `measure:` (default `:characters`)
- [ ] Two titles equal after `fold` are duplicates, so the set is numbered
- [ ] `{a: "Yes", b: "YES"}` with a downcasing fold is numbered; with the identity fold it is not
- [ ] Titles are distinct **under the fold** for every ambiguity class
- [ ] `aliases_for` is deleted — its callers stop existing in Task 3

**Verify:** `bundle exec ruby -Itest test/unit/choice_titles_test.rb` → 0 failures

**Steps:**

- [ ] **Step 1: Write the failing tests**

```ruby
# test/unit/choice_titles_test.rb — append inside the existing class
DOWNCASE = ->(s) { s.strip.downcase }

def test_titles_differing_only_by_case_are_ambiguous_under_a_downcasing_fold
  choices = {"a" => "Yes", "b" => "YES"}

  assert FlowChat::ChoiceTitles.ambiguous?(choices, 20, fold: DOWNCASE)
  refute FlowChat::ChoiceTitles.ambiguous?(choices, 20)
end

def test_numbering_makes_titles_distinct_under_the_fold
  choices = {"a" => "Yes", "b" => "YES"}
  titles = FlowChat::ChoiceTitles.build(choices, 20, fold: DOWNCASE).map { |_k, _l, t, _tr| t }

  assert_equal ["1. Yes", "2. YES"], titles
  assert_equal titles.map { |t| DOWNCASE.call(t) }.uniq.length, titles.length
end

# The Meta bug: the resolver stripped punctuation, the check did not.
def test_titles_differing_only_by_punctuation_are_ambiguous_under_a_stripping_fold
  strip = ->(s) { s.gsub(/[^\w\s]/, "").strip }
  choices = {"a" => "Yes!", "b" => "Yes"}

  assert FlowChat::ChoiceTitles.ambiguous?(choices, 20, fold: strip)
end

def test_byte_measure_numbers_a_set_that_collides_only_after_byte_truncation
  choices = {"a" => "日本語のテキストです one", "b" => "日本語のテキストです two"}

  assert FlowChat::ChoiceTitles.ambiguous?(choices, 30, measure: :bytes)
end
```

- [ ] **Step 2: Run to verify they fail**

Run: `bundle exec ruby -Itest test/unit/choice_titles_test.rb`
Expected: FAIL — `unknown keyword: :fold`

- [ ] **Step 3: Thread fold and measure through**

```ruby
# lib/flow_chat/choice_titles.rb — replace .build, .ambiguous?, .ambiguity_reason
    IDENTITY = ->(string) { string }

    # @param fold [Proc] the normalization the resolver applies before
    #   matching input. Two titles that fold to the same string cannot be
    #   told apart by that resolver, so the set is ambiguous and gets
    #   numbered - the same rule USSD gets for free by resolving on
    #   position, which is injective by construction.
    def self.build(choices, cap, fold: IDENTITY, measure: :characters)
      reason = ambiguity_reason(choices, cap, fold: fold, measure: measure)
      prefixed = !reason.nil?

      if prefixed
        FlowChat.logger.debug { "#{name}: numbering choices, titles are ambiguous (#{reason})" }
      end

      choices.map.with_index(1) do |(key, label), position|
        label = label.to_s

        if prefixed
          title = FlowChat::TextTruncator.number(label, position, cap, measure: measure)
        else
          title = FlowChat::TextTruncator.truncate(label, cap, measure: measure)
        end

        [key.to_s, label, title, title != label]
      end
    end

    def self.ambiguous?(choices, cap, fold: IDENTITY, measure: :characters)
      !ambiguity_reason(choices, cap, fold: fold, measure: measure).nil?
    end

    def self.ambiguity_reason(choices, cap, fold: IDENTITY, measure: :characters)
      labels = choices.map { |_, label| label.to_s }
      titles = labels.map { |label| FlowChat::TextTruncator.truncate(label, cap, measure: measure) }

      truncated_labels = labels.zip(titles).select { |label, title| title != label }.map(&:first)
      duplicate_titles = titles.map { |title| fold.call(title) }.tally.select { |_, count| count > 1 }.keys

      return nil if truncated_labels.empty? && duplicate_titles.empty?

      parts = []
      parts << "truncated: #{truncated_labels.inspect}" unless truncated_labels.empty?
      parts << "duplicate titles: #{duplicate_titles.inspect}" unless duplicate_titles.empty?
      parts.join(", ")
    end
```

- [ ] **Step 4: Delete `aliases_for` and its docs**

Remove `lib/flow_chat/choice_titles.rb:83-113` entirely. It has no callers after Task 3, and the guarantee it leaned on ("`.build` never hands back two identical titles") is now the guarantee the wire value itself rests on.

- [ ] **Step 5: Run the tests**

Run: `bundle exec ruby -Itest test/unit/choice_titles_test.rb`
Expected: PASS (existing `aliases_for` tests deleted alongside the method)

- [ ] **Step 6: Commit**

```bash
git add lib/flow_chat/choice_titles.rb test/unit/choice_titles_test.rb
git commit -m "feat(choices): decide ambiguity under the resolver's own equivalence"
```

---

### Task 3: Meta mappers send the displayed title, not a generated id

**Goal:** WhatsApp, Messenger and Instagram put the displayed title on the wire, so the id map and the alias map become one map and typing what is on a button always resolves to that button.

**Files:**
- Modify: `lib/flow_chat/whatsapp/middleware/choice_mapper.rb:99-236`
- Modify: `lib/flow_chat/messenger/middleware/choice_mapper.rb:93-160`
- Test: `test/unit/whatsapp/middleware/choice_mapper_test.rb`
- Test: `test/unit/messenger/middleware/choice_mapper_test.rb`
- Test: `test/unit/instagram/middleware/choice_mapper_test.rb`

**Acceptance Criteria:**
- [ ] The choices handed to the renderer are keyed by displayed title
- [ ] `whatsapp.alias_mapping`, `messenger.alias_mapping` and `instagram.alias_mapping` are gone — set, read, cleared and all
- [ ] Resolution order is title → position
- [ ] `{a: "Yes!", b: "Yes"}`: typing `Yes` resolves to **b**, typing `Yes!` resolves to **a**
- [ ] `{a: "Savings", b: "Savings"}`: titles are `1. Savings` / `2. Savings`, both resolvable and distinct
- [ ] No generated id ever exceeds the platform's id cap (256 button / 200 list row / 1000 payload)

**Verify:** `bundle exec ruby -Itest test/unit/whatsapp/middleware/choice_mapper_test.rb && bundle exec ruby -Itest test/unit/messenger/middleware/choice_mapper_test.rb && bundle exec ruby -Itest test/unit/instagram/middleware/choice_mapper_test.rb` → 0 failures

**Steps:**

- [ ] **Step 1: Write the failing regression test**

```ruby
# test/unit/whatsapp/middleware/choice_mapper_test.rb — append inside the existing class
# The review bug: IdGenerator stripped "!" from "Yes!", so choice A's id was
# choice B's label verbatim, and the id map was consulted before the alias
# map. A user typing what was printed on button B landed on A.
def test_typing_a_title_resolves_to_the_choice_that_shows_it
  mapper = build_mapper(choices: {"a" => "Yes!", "b" => "Yes"})

  assert_equal "b", resolve(mapper, "Yes")
  assert_equal "a", resolve(mapper, "Yes!")
end

def test_duplicate_labels_are_numbered_and_both_resolve
  mapper = build_mapper(choices: {"a" => "Savings", "b" => "Savings"})

  assert_equal ["1. Savings", "2. Savings"], rendered_titles(mapper)
  assert_equal "a", resolve(mapper, "1. Savings")
  assert_equal "b", resolve(mapper, "2. Savings")
  assert_equal "b", resolve(mapper, "2")
end

def test_no_alias_mapping_is_written
  mapper = build_mapper(choices: {"a" => "Yes", "b" => "No"})

  assert_nil mapper.session.get("whatsapp.alias_mapping")
end

def test_generated_ids_never_exceed_the_list_row_cap
  choices = (1..12).to_h { |i| ["k#{i}", "#{"long label " * 30}#{i}"] }
  mapper = build_mapper(choices: choices)

  rendered_titles(mapper).each do |title|
    assert_operator title.length, :<=, 200, "list row id cap is 200 characters"
  end
end
```

- [ ] **Step 2: Run to verify they fail**

Run: `bundle exec ruby -Itest test/unit/whatsapp/middleware/choice_mapper_test.rb`
Expected: FAIL — typing `Yes` resolves to `"a"`

- [ ] **Step 3: Replace WhatsApp's mapping construction**

```ruby
# lib/flow_chat/whatsapp/middleware/choice_mapper.rb — replace create_id_mapping
        # The wire value IS the displayed title. FlowChat::ChoiceTitles
        # guarantees the titles in a set are distinct - numbering the whole
        # set when they would not be - so the title needs no separate id
        # space to be unique in, and there is nothing for a generated id to
        # collide with. Titles are bounded by the rung's title cap (20 or
        # 24), comfortably inside WhatsApp's id caps (256 button, 200 row).
        def create_id_mapping(choices)
          cap = display_title_cap(choices.length)
          return passthrough_mapping(choices) if cap.nil?

          title_choices = {}
          choice_mapping = {}

          FlowChat::ChoiceTitles.build(choices, cap).each do |key, label, title, _truncated|
            title_choices[title] = label
            choice_mapping[title] = key
          end

          store_choice_mapping(choice_mapping)

          if number_choices?(choices)
            store_position_mapping(choices.keys.map.with_index(1) { |key, i| [i.to_s, key.to_s] }.to_h)
          end

          title_choices
        end

        # Above the row cap the renderer numbers the body and shows each full
        # label, so there is no title to key on and a typed number is the
        # only reply that means anything.
        def passthrough_mapping(choices)
          store_position_mapping(choices.keys.map.with_index(1) { |key, i| [i.to_s, key.to_s] }.to_h)
          choices
        end
```

- [ ] **Step 4: Collapse the resolution order**

```ruby
# lib/flow_chat/whatsapp/middleware/choice_mapper.rb — replace resolved_choice
        # Titles first, then positions. A tap sends the title as its payload
        # and a user who types what they read sends the same string, so both
        # arrive at the same map entry. A position is the fallback, and only
        # means anything when a number is genuinely on screen.
        def resolved_choice
          input = @context.input.to_s
          get_choice_mapping[input] || get_position_mapping[input]
        end
```

Delete `store_alias_mapping`, `get_alias_mapping`, `clear_alias_mapping`, and the `clear_alias_mapping` call inside `clear_choice_state`.

- [ ] **Step 5: Apply the same change to Messenger**

```ruby
# lib/flow_chat/messenger/middleware/choice_mapper.rb — replace create_mappings
        def create_mappings(choices)
          cap = display_title_cap(choices.length)
          return passthrough_mapping(choices) if cap.nil?

          title_choices = {}
          id_mapping = {}

          FlowChat::ChoiceTitles.build(choices, cap).each do |key, label, title, _truncated|
            title_choices[title] = label
            id_mapping[title] = key
          end

          @session.set(id_key, id_mapping)

          if number_choices?(choices)
            @session.set(position_key, choices.keys.map.with_index(1) { |key, i| [i.to_s, key.to_s] }.to_h)
          else
            @session.delete(position_key)
          end

          title_choices
        end

        def passthrough_mapping(choices)
          @session.set(position_key, choices.keys.map.with_index(1) { |key, i| [i.to_s, key.to_s] }.to_h)
          choices
        end
```

```ruby
# lib/flow_chat/messenger/middleware/choice_mapper.rb — replace resolved_choice
        def resolved_choice
          input = @context.input.to_s
          return nil if input.empty?

          get_id_mapping[input] || get_position_mapping[input]
        end
```

Delete `ALIAS_KEY`, `alias_key`, `get_alias_mapping` and its `clear_mappings` line. Instagram's subclass (`lib/flow_chat/instagram/middleware/choice_mapper.rb:6`) declares its own `ALIAS_KEY` — delete that constant too.

- [ ] **Step 6: Rewrite the three stale precedence comments**

The block at `whatsapp/middleware/choice_mapper.rb:99-107`, the one at `messenger/middleware/choice_mapper.rb:7-15`, and the one at `messenger/middleware/choice_mapper.rb:93-101` all describe an id/alias/position ordering that no longer exists, and all three state the invariant one word too narrow ("never registers an alias equal to **its own** choice's generated id"). Replace each with the two-map explanation from Step 4.

- [ ] **Step 7: Run the tests**

Run: `bundle exec ruby -Itest test/unit/whatsapp/middleware/choice_mapper_test.rb && bundle exec ruby -Itest test/unit/messenger/middleware/choice_mapper_test.rb && bundle exec ruby -Itest test/unit/instagram/middleware/choice_mapper_test.rb`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add lib/flow_chat/whatsapp lib/flow_chat/messenger lib/flow_chat/instagram test/unit/whatsapp test/unit/messenger test/unit/instagram
git commit -m "fix(choices): send the title users read, not a lossy copy of it"
```

---

### Task 4: Delete IdGenerator

**Goal:** Remove the class whose lossy normalization caused the bug, now that nothing calls it.

**Files:**
- Delete: `lib/flow_chat/id_generator.rb`
- Delete: `test/unit/id_generator_test.rb`
- Modify: `lib/flow_chat.rb` (remove the require, if one exists)

**Acceptance Criteria:**
- [ ] `grep -rn "IdGenerator" lib/ test/` returns nothing
- [ ] Full suite passes

**Verify:** `grep -rn "IdGenerator" lib/ test/ ; bundle exec rake test` → no matches, 0 failures

**Steps:**

- [ ] **Step 1: Confirm there are no remaining callers**

Run: `grep -rn "IdGenerator" lib/ test/`
Expected: no output. If anything remains, it belongs to Task 3 and must be finished first.

- [ ] **Step 2: Delete the files**

```bash
git rm lib/flow_chat/id_generator.rb test/unit/id_generator_test.rb
```

- [ ] **Step 3: Drop the require**

Run: `grep -n "id_generator" lib/flow_chat.rb` and delete the matching line if present.

- [ ] **Step 4: Run the full suite**

Run: `bundle exec rake test`
Expected: 0 failures

- [ ] **Step 5: Commit**

```bash
git commit -am "refactor(choices): drop the id generator the titles replaced"
```

---

### Task 5: HTTP mapper adopts the fold

**Goal:** HTTP stops silently dropping the second of two labels that match case-insensitively.

**Files:**
- Modify: `lib/flow_chat/http/middleware/choice_mapper.rb:36-66`
- Test: `test/unit/http/middleware/choice_mapper_test.rb`

**Acceptance Criteria:**
- [ ] Labels that fold to the same string cause the set to be numbered
- [ ] `{a: "Savings", b: "Savings"}` → both resolvable, neither dropped
- [ ] `{a: "Yes", b: "YES"}` → both resolvable
- [ ] A key still resolves by passing through unmapped, as today
- [ ] No `||=` remains in `remember`

**Verify:** `bundle exec ruby -Itest test/unit/http/middleware/choice_mapper_test.rb` → 0 failures

**Note:** this changes what a web client displays for a colliding set — it will receive `1. Savings` / `2. Savings` rather than two identical labels. That is the point: two identical labels are indistinguishable to whoever is reading them.

**Steps:**

- [ ] **Step 1: Write the failing test**

```ruby
# test/unit/http/middleware/choice_mapper_test.rb — append inside the existing class
def test_duplicate_labels_are_numbered_rather_than_dropped
  mapper = build_mapper(choices: {"a" => "Savings", "b" => "Savings"})

  assert_equal "a", resolve(mapper, "1. Savings")
  assert_equal "b", resolve(mapper, "2. Savings")
end

def test_labels_differing_only_by_case_both_resolve
  mapper = build_mapper(choices: {"a" => "Yes", "b" => "YES"})

  assert_equal "a", resolve(mapper, "1. Yes")
  assert_equal "b", resolve(mapper, "2. YES")
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bundle exec ruby -Itest test/unit/http/middleware/choice_mapper_test.rb`
Expected: FAIL — both inputs resolve to `"a"`, or neither resolves

- [ ] **Step 3: Fold, number, and drop the first-wins**

```ruby
# lib/flow_chat/http/middleware/choice_mapper.rb — replace remember
        FOLD = ->(string) { string.strip.downcase }

        # A client renders these itself, so the cap is the flow's own labels
        # rather than a platform limit - nothing is truncated here. What the
        # fold buys is duplicate detection: two labels a visitor cannot tell
        # apart are numbered, rather than the second silently losing to the
        # first as it did under `||=`.
        def remember(context, choices)
          if choices.blank?
            context.session.delete(SESSION_KEY)
            return
          end

          mapping = {}
          FlowChat::ChoiceTitles.build(choices, UNCAPPED, fold: FOLD).each do |key, _label, title, _truncated|
            mapping[FOLD.call(title)] = key
          end

          context.session.set(SESSION_KEY, mapping)
          FlowChat.logger.debug { "Http::ChoiceMapper: Created mapping: #{mapping}" }
        end
```

Add `UNCAPPED = Float::INFINITY` beside `SESSION_KEY`, and make `remember` return the numbered choices so the client renders what the mapper resolves — mirroring how the Meta mappers hand back their transformed set. Wire that through `call`:

```ruby
        def call(context)
          resolve_input(context)

          type, prompt, choices, media = @app.call(context)

          choices = remember(context, choices)

          [type, prompt, choices, media]
        end
```

- [ ] **Step 4: Run the tests**

Run: `bundle exec ruby -Itest test/unit/http/middleware/choice_mapper_test.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/flow_chat/http test/unit/http
git commit -m "fix(http): stop the second of two matching labels losing silently"
```

---

### Task 6: Intercom mapper adopts the fold

**Goal:** Same fix for Intercom, which carries the identical `||=` first-wins drop.

**Files:**
- Modify: `lib/flow_chat/intercom/middleware/choice_mapper.rb:57-75`
- Test: `test/unit/intercom/middleware/choice_mapper_test.rb`

**Acceptance Criteria:**
- [ ] Duplicate labels both resolve; neither is dropped
- [ ] A bare position number still resolves, as today
- [ ] No `||=` remains in `remember`
- [ ] The comment claiming "the first wins, as it does on the screen" is gone — it no longer does

**Verify:** `bundle exec ruby -Itest test/unit/intercom/middleware/choice_mapper_test.rb` → 0 failures

**Steps:**

- [ ] **Step 1: Write the failing test**

```ruby
# test/unit/intercom/middleware/choice_mapper_test.rb — append inside the existing class
def test_duplicate_labels_both_resolve
  mapper = build_mapper(choices: {"a" => "Savings", "b" => "Savings"})

  assert_equal "a", resolve(mapper, "1")
  assert_equal "b", resolve(mapper, "2")
  assert_equal "b", resolve(mapper, "2. Savings")
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bundle exec ruby -Itest test/unit/intercom/middleware/choice_mapper_test.rb`
Expected: FAIL on the `"2. Savings"` assertion

- [ ] **Step 3: Build the mapping from titles**

```ruby
# lib/flow_chat/intercom/middleware/choice_mapper.rb — replace remember
        FOLD = ->(string) { string.strip.downcase }

        # Intercom always numbers, so the titles this builds are always
        # distinct and every one of them is resolvable - which is what
        # replaces the old `||=`, where a repeated label meant the second
        # choice could not be picked by name at all.
        def remember(choices)
          numbered = {}
          mapping = {}

          FlowChat::ChoiceTitles.build(choices, UNCAPPED, fold: FOLD).each_with_index do |(key, _label, title, _truncated), index|
            number = (index + 1).to_s
            numbered[number] = title
            mapping[number] = key
            mapping[FOLD.call(title)] = key
          end

          @session.set(SESSION_KEY, mapping)
          FlowChat.logger.debug { "Intercom::ChoiceMapper: Created mapping: #{mapping}" }
          numbered
        end
```

Add `UNCAPPED = Float::INFINITY` beside `SESSION_KEY`.

- [ ] **Step 4: Run the tests**

Run: `bundle exec ruby -Itest test/unit/intercom/middleware/choice_mapper_test.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/flow_chat/intercom test/unit/intercom
git commit -m "fix(intercom): let a repeated label still be picked by name"
```

---

### Task 7: Telegram resolves against a real map, sized in bytes

**Goal:** Telegram stops overflowing its 64-byte field on multibyte keys and stops making a choice unselectable when two keys share a prefix.

**Files:**
- Modify: `lib/flow_chat/telegram/middleware/choice_mapper.rb` (whole file)
- Modify: `lib/flow_chat/telegram/renderer.rb:75-80`
- Test: `test/unit/telegram/middleware/choice_mapper_test.rb`

**Acceptance Criteria:**
- [ ] `callback_data` never exceeds 64 bytes for any input, including emoji and CJK labels
- [ ] `callback_data` is always valid UTF-8
- [ ] Two labels sharing a 64-byte prefix are numbered, and both resolve
- [ ] The mapper rewrites `context.input` to the flow's key, rather than passing raw `callback_data` through
- [ ] A typed position still resolves

**Verify:** `bundle exec ruby -Itest test/unit/telegram/middleware/choice_mapper_test.rb` → 0 failures

**Steps:**

- [ ] **Step 1: Write the failing tests**

```ruby
# test/unit/telegram/middleware/choice_mapper_test.rb — append inside the existing class
CALLBACK_DATA_LIMIT = 64

def test_callback_data_fits_the_byte_limit_for_multibyte_labels
  mapper = build_mapper(choices: {"a" => "日本語のテキストです " * 5})

  wire_values(mapper).each do |value|
    assert_operator value.bytesize, :<=, CALLBACK_DATA_LIMIT
    assert value.valid_encoding?
  end
end

def test_labels_sharing_a_long_prefix_are_numbered_and_both_resolve
  shared = "Transfer to the account ending in " * 3
  mapper = build_mapper(choices: {"a" => "#{shared} one", "b" => "#{shared} two"})

  values = wire_values(mapper)
  assert_equal values.uniq.length, values.length, "callback_data must stay distinct after truncation"
  assert_equal "a", resolve(mapper, values[0])
  assert_equal "b", resolve(mapper, values[1])
end
```

- [ ] **Step 2: Run to verify they fail**

Run: `bundle exec ruby -Itest test/unit/telegram/middleware/choice_mapper_test.rb`
Expected: FAIL — `callback_data` exceeds 64 bytes, and the two values are identical

- [ ] **Step 3: Give the mapper real maps**

```ruby
# lib/flow_chat/telegram/middleware/choice_mapper.rb — replace the class body
      # Telegram's callback_data is 1-64 *bytes*, not characters, and carries
      # no character restrictions. Sizing it in characters let a multibyte
      # label through to be rejected, and slicing the key at 64 characters
      # let two long keys collapse onto one callback_data - which resolved to
      # neither, so the choice could not be picked at all.
      #
      # Numbering is what keeps them apart, because a position prefix sits at
      # the front and survives a cut from the right; a hash suffix would not.
      class ChoiceMapper
        SESSION_KEY = "telegram.choice_mapping"
        POSITION_KEY = "telegram.position_mapping"
        CALLBACK_DATA_LIMIT = 64

        def initialize(app)
          @app = app
        end

        def call(context)
          @context = context
          @session = context.session

          resolve_input

          type, prompt, choices, media = @app.call(context)

          choices = remember(choices) if choices.present?

          [type, prompt, choices, media]
        end

        private

        def resolve_input
          return if @context.input.blank?

          input = @context.input.to_s
          resolved = mapping[input] || positions[input]
          return unless resolved

          FlowChat.logger.info { "Telegram::ChoiceMapper: Resolving #{input} to #{resolved}" }
          @context.input = resolved
        end

        def remember(choices)
          wire_choices = {}
          choice_mapping = {}

          FlowChat::ChoiceTitles.build(choices, CALLBACK_DATA_LIMIT, measure: :bytes).each do |key, _label, title, _truncated|
            wire_choices[title] = title
            choice_mapping[title] = key
          end

          @session.set(SESSION_KEY, choice_mapping)
          @session.set(POSITION_KEY, choices.keys.map.with_index(1) { |key, i| [i.to_s, key.to_s] }.to_h)

          wire_choices
        end

        def mapping
          @session.get(SESSION_KEY) || {}
        end

        def positions
          @session.get(POSITION_KEY) || {}
        end
      end
```

- [ ] **Step 4: Stop the renderer re-truncating by characters**

```ruby
# lib/flow_chat/telegram/renderer.rb:75-80 — replace
        buttons = choice_hash.map do |key, value|
          {
            text: FlowChat::TextTruncator.truncate(value.to_s, 64, measure: :bytes),
            callback_data: key.to_s
          }
        end
```

The mapper has already sized the key to 64 bytes, so `callback_data` needs no further cutting — cutting it again here is what reintroduces collisions.

- [ ] **Step 5: Run the tests**

Run: `bundle exec ruby -Itest test/unit/telegram/middleware/choice_mapper_test.rb`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/flow_chat/telegram test/unit/telegram
git commit -m "fix(telegram): size callback data in bytes and keep it distinct"
```

---

### Task 8: Pin USSD's exemption

**Goal:** Record why USSD is the one mapper that needs no fold, so a later change does not "unify" it into a bug.

**Files:**
- Modify: `lib/flow_chat/ussd/middleware/choice_mapper.rb:60-70` (comment only)
- Test: `test/unit/ussd/middleware/choice_mapper_test.rb`

**Acceptance Criteria:**
- [ ] A test proves duplicate labels still resolve distinctly on USSD
- [ ] The comment states the invariant: USSD resolves on position, which is injective by construction

**Verify:** `bundle exec ruby -Itest test/unit/ussd/middleware/choice_mapper_test.rb` → 0 failures

**Steps:**

- [ ] **Step 1: Write the test**

```ruby
# test/unit/ussd/middleware/choice_mapper_test.rb — append inside the existing class
# USSD needs no fold and no aliasing: a numeric keypad only ever sends a
# position, and positions are unique by construction. That is the same
# invariant every other mapper now has to be given explicitly.
def test_duplicate_labels_still_resolve_distinctly
  mapper = build_mapper(choices: {"a" => "Savings", "b" => "Savings"})

  assert_equal "a", resolve(mapper, "1")
  assert_equal "b", resolve(mapper, "2")
end
```

- [ ] **Step 2: Run it**

Run: `bundle exec ruby -Itest test/unit/ussd/middleware/choice_mapper_test.rb`
Expected: PASS immediately — this pins existing behaviour rather than changing it

- [ ] **Step 3: Add the invariant comment**

```ruby
        # USSD is deliberately exempt from the fold every other mapper takes.
        # A numeric keypad can only send a position, and positions are unique
        # by construction, so the relation this resolves on is already
        # injective - there is no equivalence under which two choices could
        # collapse. Every other mapper has to be *given* that guarantee, by
        # numbering a set whose titles collide under its own fold.
        def create_numbered_mapping(choices)
```

- [ ] **Step 4: Commit**

```bash
git add lib/flow_chat/ussd test/unit/ussd
git commit -m "docs(ussd): record why position resolution needs no aliasing"
```

---

### Task 9: Update the choice documentation

**Goal:** Bring the docs in line, including the two stale comments found during review.

**Files:**
- Modify: `docs/platforms/whatsapp.md`, `docs/platforms/telegram.md` (choice sections)
- Modify: `docs/gateway-development.md` (choice mapper contract)

**Acceptance Criteria:**
- [ ] No doc refers to generated ids, alias maps, or `IdGenerator`
- [ ] The fold/measure contract is documented for anyone writing a new gateway
- [ ] The USSD exemption is stated

**Verify:** `grep -rn "IdGenerator\|alias_mapping" docs/ --include=*.md | grep -v superpowers/` → no matches

**Steps:**

- [ ] **Step 1: Find every stale reference**

Run: `grep -rn "IdGenerator\|alias mapping\|alias_mapping\|generated id" docs/ --include=*.md | grep -v superpowers/`

- [ ] **Step 2: Rewrite the choice-mapper contract in `docs/gateway-development.md`**

State the invariant plainly: a gateway's choice mapper must pass `ChoiceTitles` the same fold its resolver matches on, and the same measure its platform sizes fields in. Give the four folds in use — identity (Meta), `strip.downcase` (HTTP, Intercom), byte-truncation (Telegram), position (USSD, exempt).

- [ ] **Step 3: Commit**

```bash
git add docs/
git commit -m "docs(choices): describe the fold a mapper owes its resolver"
```

---

## Out of scope

Two defects found in the same review are independent of this plan and are **not** addressed here. Track them separately:

- **`message.sent` fires on a failed delivery** — `report_delivery_failure` returns `nil`, but callers instrument `MESSAGE_SENT` regardless (`lib/flow_chat/instrumentation.rb:61`, `lib/flow_chat/meta/messaging_gateway.rb:373`, plus the WhatsApp, Intercom and Telegram equivalents).
- **Async double-publishes status/echo events** — the foreground pass publishes them before enqueueing, and the background job republishes them (`lib/flow_chat/meta/messaging_gateway.rb:220`; mirrored in `whatsapp/gateway/cloud_api.rb`).

Also unaddressed, and worth a line when someone next touches markdown rendering: `renderers/markdown_support.rb:80`'s non-greedy `<ul>` regex leaks raw tags on nested lists.

require "test_helper"

module FlowChat
  module Messenger
    module Middleware
      class ChoiceMapperTest < Minitest::Test
        def setup
          @app = Minitest::Mock.new
          @middleware = ChoiceMapper.new(@app)
          @session = MockSession.new
          @context = MockContext.new(@session)
        end

        def test_tapped_quick_reply_resolves_to_the_original_key
          choices = {"create" => "Create Account", "login" => "Log In"}
          @app.expect :call, [:prompt, "Pick", choices, nil], [@context]

          @middleware.call(@context)

          tapped = @session.get("messenger.choice_mapping").keys.first
          @context.input = tapped
          @app.expect :call, [:text, "response", nil, nil], [@context]

          @middleware.call(@context)

          assert_equal "create", @context.input
          @app.verify
        end

        def test_typed_number_resolves_on_the_numbered_rung
          choices = (1..31).to_h { |i| ["k#{i}", "Option #{i}"] }
          @app.expect :call, [:prompt, "Pick", choices, nil], [@context]

          @middleware.call(@context)

          @context.input = "3"
          @app.expect :call, [:text, "response", nil, nil], [@context]

          @middleware.call(@context)

          assert_equal "k3", @context.input
          @app.verify
        end

        # A generated id and a position occupy the same key space:
        # IdGenerator#normalize_label keeps \w, which includes digits, so a
        # choice labelled "5" generates the id "5". Ids must win: the id map is
        # consulted before the position map.
        #
        # A position map is stored on every rung now, so this collision is
        # live everywhere, not only on the numbered rung; exercising it here
        # above 30 choices (the numbered rung) reuses the exact scenario
        # a1d08a4 documented. A "special" choice labelled "5" sits first
        # (position "1"), while a different choice, "k4", sits at position
        # "5" - so typing "5" finds two different answers depending on which
        # map wins.
        def test_generated_ids_win_over_positions
          choices = {"special" => "5"}.merge((1..30).to_h { |i| ["k#{i}", "Option #{i}"] })
          @app.expect :call, [:prompt, "Pick", choices, nil], [@context]

          @middleware.call(@context)

          assert_equal "k4", @session.get("messenger.position_mapping")["5"],
            "test setup assumption: position 5 is the choice \"k4\""

          @context.input = "5"
          @app.expect :call, [:text, "response", nil, nil], [@context]

          @middleware.call(@context)

          assert_equal "special", @context.input, "the id for the label \"5\" must win over position 5"
          @app.verify
        end

        # The renderer prefixes a quick reply title with its position and
        # truncates to limits.max_quick_reply_title (20), so a user who types
        # exactly what they see (rather than the full, unprefixed label the
        # id was generated from) must still resolve.
        def test_typed_truncated_quick_reply_title_resolves
          long_label = "A label that is definitely longer than twenty chars"
          choices = {"a" => long_label, "b" => "Beta"}
          @app.expect :call, [:prompt, "Pick", choices, nil], [@context]

          @middleware.call(@context)

          @context.input = "1. A label that i..." # 20 chars, as Messenger renders it on a quick reply
          @app.expect :call, [:text, "response", nil, nil], [@context]

          @middleware.call(@context)

          assert_equal "a", @context.input
          @app.verify
        end

        # On the carousel rung the truncation cap is limits.max_button_title
        # (also 20), applied to each option's button rather than a quick
        # reply.
        def test_typed_truncated_carousel_button_title_resolves
          long_label = "A label that is definitely longer than twenty chars"
          choices = {"a" => long_label}.merge((2..14).to_h { |i| ["k#{i}", "Option #{i}"] })
          @app.expect :call, [:prompt, "Pick", choices, nil], [@context]

          @middleware.call(@context)

          @context.input = "1. A label that i..."
          @app.expect :call, [:text, "response", nil, nil], [@context]

          @middleware.call(@context)

          assert_equal "a", @context.input
          @app.verify
        end

        # a1d08a4 could alias neither of these labels, because both truncate
        # to the same "A label that is d..." at a 20-char cap. The position
        # prefix makes the two titles distinct by construction, so both
        # resolve now.
        def test_labels_that_would_have_collided_without_a_prefix_both_resolve
          choices = {
            "a" => "A label that is definitely one thing",
            "b" => "A label that is definitely another"
          }

          [["a", "1. A label that i..."], ["b", "2. A label that i..."]].each do |expected_key, typed|
            setup
            @app.expect :call, [:prompt, "Pick", choices, nil], [@context]
            @middleware.call(@context)

            @context.input = typed
            @app.expect :call, [:text, "response", nil, nil], [@context]
            @middleware.call(@context)

            assert_equal expected_key, @context.input
            @app.verify
          end
        end

        # Round-trip: render the actual payload, take each title exactly as
        # Messenger would display it, feed it back as typed input, and
        # confirm it resolves to the choice that produced it. This is the
        # loop that a renderer/mapper disagreement on numbering would break
        # silently.
        def test_round_trip_quick_reply_titles_resolve_including_the_pair_that_used_to_collide
          choices = {
            "savings" => "Transfer to savings account",
            "salary" => "Transfer to salary account"
          }

          [["savings", 0], ["salary", 1]].each do |expected_key, reply_index|
            setup
            @app.expect :call, [:prompt, "Pick", choices, nil], [@context]
            _, prompt, transformed, _ = @middleware.call(@context)

            rendered = FlowChat::Messenger::Renderer.new(prompt, choices: transformed).render
            title = rendered[2][:quick_replies][reply_index][:title]
            assert_operator title.length, :<=, platform_limits.max_quick_reply_title

            @context.input = title
            @app.expect :call, [:text, "response", nil, nil], [@context]
            @middleware.call(@context)

            assert_equal expected_key, @context.input,
              "typing the displayed title #{title.inspect} must resolve to #{expected_key.inspect}"
            @app.verify
          end
        end

        # Same loop, one rung up: more than 13 choices renders a carousel
        # instead of quick replies.
        def test_round_trip_carousel_button_titles_resolve_including_the_pair_that_used_to_collide
          choices = {
            "savings" => "Transfer to savings account",
            "salary" => "Transfer to salary account"
          }.merge((3..14).to_h { |i| ["k#{i}", "Option #{i}"] })

          [["savings", 0], ["salary", 1]].each do |expected_key, button_index|
            setup
            @app.expect :call, [:prompt, "Pick", choices, nil], [@context]
            _, prompt, transformed, _ = @middleware.call(@context)

            rendered = FlowChat::Messenger::Renderer.new(prompt, choices: transformed).render
            title = rendered[2][:elements][0][:buttons][button_index][:title]
            assert_operator title.length, :<=, platform_limits.max_button_title

            @context.input = title
            @app.expect :call, [:text, "response", nil, nil], [@context]
            @middleware.call(@context)

            assert_equal expected_key, @context.input,
              "typing the displayed button title #{title.inspect} must resolve to #{expected_key.inspect}"
            @app.verify
          end
        end

        # The savings/salary pair is ambiguous (truncation), so the screen is
        # numbered: typing the bare position, not just the full displayed
        # title, must also resolve.
        def test_typed_position_resolves_on_an_ambiguous_quick_reply_rung
          choices = {
            "savings" => "Transfer to savings account",
            "salary" => "Transfer to salary account"
          }
          @app.expect :call, [:prompt, "Pick", choices, nil], [@context]
          @middleware.call(@context)

          @context.input = "2"
          @app.expect :call, [:text, "response", nil, nil], [@context]
          @middleware.call(@context)

          assert_equal "salary", @context.input
          @app.verify
        end

        # The duplicate-label case: no truncation is involved at all - both
        # labels are "Accept", well under the 20-char quick-reply cap - but
        # sharing a label is exactly as ambiguous as a truncation collision,
        # so FlowChat::ChoiceTitles prefixes the whole set. Without the
        # duplicate trigger this would render two identical "Accept" quick
        # replies whose aliases collide, silently resolving to whichever
        # choice's alias happened to be written last.
        def test_round_trip_duplicate_labels_each_resolve_to_their_own_distinct_key
          choices = {"yes" => "Accept", "no" => "Accept"}

          [["yes", 0], ["no", 1]].each do |expected_key, reply_index|
            setup
            @app.expect :call, [:prompt, "Pick", choices, nil], [@context]
            _, prompt, transformed, _ = @middleware.call(@context)

            rendered = FlowChat::Messenger::Renderer.new(prompt, choices: transformed).render
            title = rendered[2][:quick_replies][reply_index][:title]
            assert_equal "#{reply_index + 1}. Accept", title, "the screen must be numbered when labels are duplicated"

            @context.input = title
            @app.expect :call, [:text, "response", nil, nil], [@context]
            @middleware.call(@context)

            assert_equal expected_key, @context.input,
              "typing the displayed title #{title.inspect} must resolve to its own choice, not the other \"Accept\""
            @app.verify
          end
        end

        # Contrast with the ambiguous cases above: "Alpha" and "Beta" are
        # short and distinct, so the screen is not numbered at all. The
        # displayed title still round-trips (it resolves via the id map,
        # since the bare title equals the choice's own generated id here),
        # but a typed bare digit is free text - no number was ever shown, so
        # there is nothing for it to be a position of.
        def test_round_trip_unambiguous_quick_reply_rung_has_no_position
          choices = {"a" => "Alpha", "b" => "Beta"}
          @app.expect :call, [:prompt, "Pick", choices, nil], [@context]
          _, prompt, transformed, _ = @middleware.call(@context)

          rendered = FlowChat::Messenger::Renderer.new(prompt, choices: transformed).render
          title = rendered[2][:quick_replies][1][:title]
          assert_equal "Beta", title, "an unambiguous title is not prefixed"

          @context.input = title
          @app.expect :call, [:text, "response", nil, nil], [@context]
          @middleware.call(@context)
          assert_equal "b", @context.input, "the displayed title must still round-trip"

          setup
          @app.expect :call, [:prompt, "Pick", choices, nil], [@context]
          @middleware.call(@context)

          @context.input = "1"
          @app.expect :call, [:text, "response", nil, nil], [@context]
          @middleware.call(@context)
          assert_equal "1", @context.input,
            "no number was shown, so a typed digit must stay free text, not resolve to a position"
          @app.verify
        end

        # On the numbered rung (above the carousel capacity) there is no
        # separate title to alias, only the position printed in the body;
        # the round trip there is pulling that number back out of the
        # rendered body, exactly as a user reading it would, and typing it
        # back.
        def test_round_trip_numbered_body_position_resolves
          choices = (1..31).to_h { |i| ["k#{i}", "Option #{i}"] }
          @app.expect :call, [:prompt, "Pick", choices, nil], [@context]

          _, prompt, transformed, _ = @middleware.call(@context)

          rendered = FlowChat::Messenger::Renderer.new(prompt, choices: transformed).render
          third_numbered_line = rendered[1].lines.grep(/^\d+\. /)[2]
          typed_position = third_numbered_line[/^\d+/]

          @context.input = typed_position
          @app.expect :call, [:text, "response", nil, nil], [@context]
          @middleware.call(@context)

          assert_equal "k3", @context.input
          @app.verify
        end

        # Precedence must be id, then alias, then position, no matter which
        # maps happen to hold the same key.
        def test_generated_ids_win_over_aliases
          @session.set("messenger.choice_mapping", {"tied" => "from_id"})
          @session.set("messenger.alias_mapping", {"tied" => "from_alias"})
          @session.set("messenger.position_mapping", {"tied" => "from_position"})
          @context.input = "tied"
          @app.expect :call, [:text, "response", nil, nil], [@context]

          @middleware.call(@context)

          assert_equal "from_id", @context.input
          @app.verify
        end

        def test_aliases_win_over_positions
          @session.set("messenger.alias_mapping", {"tied" => "from_alias"})
          @session.set("messenger.position_mapping", {"tied" => "from_position"})
          @context.input = "tied"
          @app.expect :call, [:text, "response", nil, nil], [@context]

          @middleware.call(@context)

          assert_equal "from_alias", @context.input
          @app.verify
        end

        # Mirrors test_stale_maps_do_not_hijack_a_later_free_text_digit: once
        # the alias resolves, @context.input becomes the choice key, which no
        # longer matches any stored map, so the next call's
        # clear_mappings_if_needed clears everything, including the alias map.
        def test_stale_alias_map_does_not_hijack_a_later_free_text_reply
          long_label = "A label that is definitely longer than twenty chars"
          choices = {"a" => long_label, "b" => "Beta"}
          @app.expect :call, [:prompt, "Pick", choices, nil], [@context]
          @middleware.call(@context)

          @context.input = "1. A label that i..."
          @app.expect :call, [:prompt, "How many bags?", nil, nil], [@context]
          @middleware.call(@context)

          assert_equal "a", @context.input

          @context.input = "1. A label that i..."
          @app.expect :call, [:text, "response", nil, nil], [@context]
          @middleware.call(@context)

          assert_equal "1. A label that i...", @context.input,
            "a stale alias mapping must not rewrite free text on a later screen"
          @app.verify
        end

        # No number is on screen for a short, unique set of titles, so a
        # typed digit here is free text, not a position: storing one anyway
        # would let a coincidental digit hijack a reply it was never meant
        # to resolve.
        def test_no_position_map_on_an_unambiguous_quick_reply_rung
          choices = {"a" => "Alpha", "b" => "Beta"}
          @app.expect :call, [:prompt, "Pick", choices, nil], [@context]

          @middleware.call(@context)

          assert_nil @session.get("messenger.position_mapping")
          @app.verify
        end

        # Contrast with the test above: FlowChat::ChoiceTitles.ambiguous?
        # decides a set needs numbering, so the position map is stored for
        # it, on the same quick-reply rung that has none when unambiguous.
        def test_position_map_exists_on_an_ambiguous_quick_reply_rung
          choices = {"a" => "Accept", "b" => "Accept"}
          @app.expect :call, [:prompt, "Pick", choices, nil], [@context]

          @middleware.call(@context)

          assert_equal "a", @session.get("messenger.position_mapping")["1"]
          assert_equal "b", @session.get("messenger.position_mapping")["2"]
          @app.verify
        end

        # Both maps must clear together. create_mappings only runs when the
        # next screen HAS choices, so a screen without them clears nothing
        # unless clearing is explicit. This was a real bug in the WhatsApp
        # mapper, found and fixed in Task 6: read
        # lib/flow_chat/whatsapp/middleware/choice_mapper.rb for the mechanism
        # this mirrors. The turn that ADVANCES the flow (here, the turn that
        # resolves the tapped "3") is the one whose app returns the
        # choice-less prompt, matching the WhatsApp regression test.
        def test_stale_maps_do_not_hijack_a_later_free_text_digit
          choices = (1..31).to_h { |i| ["k#{i}", "Option #{i}"] }
          @app.expect :call, [:prompt, "Pick", choices, nil], [@context]

          @middleware.call(@context)

          @context.input = "3"
          @app.expect :call, [:prompt, "How many bags?", nil, nil], [@context]

          @middleware.call(@context)

          assert_equal "k3", @context.input

          @context.input = "3"
          @app.expect :call, [:text, "response", nil, nil], [@context]

          @middleware.call(@context)

          assert_equal "3", @context.input,
            "a typed digit on a screen with no choices must stay the digit, " \
            "but a stale mapping rewrote it to #{@context.input.inspect}"
          @app.verify
        end

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

        def platform_limits
          FlowChat::Config.messenger
        end

        # Mock classes for testing, mirroring
        # test/unit/whatsapp/middleware/choice_mapper_test.rb.
        class MockSession
          def initialize
            @data = {}
          end

          def get(key)
            @data[key]
          end

          def set(key, value)
            @data[key] = value
          end

          def delete(key)
            @data.delete(key)
          end
        end

        class MockContext
          attr_accessor :input
          attr_reader :session

          def initialize(session)
            @session = session
            @data = {}
            @input = nil
          end

          def [](key)
            @data[key]
          end

          def []=(key, value)
            @data[key] = value
          end
        end
      end
    end
  end
end

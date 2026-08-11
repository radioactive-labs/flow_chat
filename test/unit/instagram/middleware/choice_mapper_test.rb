require "test_helper"

module FlowChat
  module Instagram
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

          tapped = @session.get("instagram.choice_mapping").keys.first
          @context.input = tapped
          @app.expect :call, [:text, "response", nil, nil], [@context]

          @middleware.call(@context)

          assert_equal "create", @context.input
          @app.verify
        end

        # Unlike Messenger, Instagram always numbers the body, so a position
        # map must exist even on the quick-reply rung: a typed number is a
        # valid reply on every screen with choices, not only above the
        # carousel capacity.
        def test_position_map_exists_on_the_quick_reply_rung
          choices = {"a" => "Alpha", "b" => "Beta"}
          @app.expect :call, [:prompt, "Pick", choices, nil], [@context]

          @middleware.call(@context)

          assert_equal "a", @session.get("instagram.position_mapping")["1"]
          assert_equal "b", @session.get("instagram.position_mapping")["2"]
          @app.verify
        end

        # Same alias mechanism as Messenger's mapper (Instagram inherits it
        # unchanged), but exercised here on the quick-reply rung, which on
        # Instagram is reachable with as few as two choices since numbering
        # is always on.
        def test_typed_truncated_quick_reply_title_resolves
          long_label = "A label that is definitely longer than twenty chars"
          choices = {"a" => long_label, "b" => "Beta"}
          @app.expect :call, [:prompt, "Pick", choices, nil], [@context]

          @middleware.call(@context)

          @context.input = "1. A label that i..." # 20 chars, as Instagram renders it on a quick reply
          @app.expect :call, [:text, "response", nil, nil], [@context]

          @middleware.call(@context)

          assert_equal "a", @context.input
          @app.verify
        end

        # a1d08a4 could alias neither of these labels on Instagram either,
        # for the same reason as on Messenger: both truncate to the same
        # "A label that is d..." at a 20-char cap. The position prefix makes
        # the two titles distinct by construction, so both resolve now.
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
        # Instagram would display it, feed it back as typed input, and
        # confirm it resolves to the choice that produced it.
        def test_round_trip_quick_reply_titles_resolve_including_the_pair_that_used_to_collide
          choices = {
            "savings" => "Transfer to savings account",
            "salary" => "Transfer to salary account"
          }

          [["savings", 0], ["salary", 1]].each do |expected_key, reply_index|
            setup
            @app.expect :call, [:prompt, "Pick", choices, nil], [@context]
            _, prompt, transformed, _ = @middleware.call(@context)

            rendered = FlowChat::Instagram::Renderer.new(prompt, choices: transformed).render
            title = rendered[2][:quick_replies][reply_index][:title]
            assert_operator title.length, :<=, FlowChat::Config.instagram.max_quick_reply_title

            @context.input = title
            @app.expect :call, [:text, "response", nil, nil], [@context]
            @middleware.call(@context)

            assert_equal expected_key, @context.input,
              "typing the displayed title #{title.inspect} must resolve to #{expected_key.inspect}"
            @app.verify
          end
        end

        # Same loop on the carousel rung.
        def test_round_trip_carousel_button_titles_resolve_including_the_pair_that_used_to_collide
          choices = {
            "savings" => "Transfer to savings account",
            "salary" => "Transfer to salary account"
          }.merge((3..14).to_h { |i| ["k#{i}", "Option #{i}"] })

          [["savings", 0], ["salary", 1]].each do |expected_key, button_index|
            setup
            @app.expect :call, [:prompt, "Pick", choices, nil], [@context]
            _, prompt, transformed, _ = @middleware.call(@context)

            rendered = FlowChat::Instagram::Renderer.new(prompt, choices: transformed).render
            title = rendered[2][:elements][0][:buttons][button_index][:title]
            assert_operator title.length, :<=, FlowChat::Config.instagram.max_button_title

            @context.input = title
            @app.expect :call, [:text, "response", nil, nil], [@context]
            @middleware.call(@context)

            assert_equal expected_key, @context.input,
              "typing the displayed button title #{title.inspect} must resolve to #{expected_key.inspect}"
            @app.verify
          end
        end

        # The savings/salary pair is ambiguous (truncation), so its titles
        # are numbered: typing the bare position, not just the full
        # displayed title, must also resolve.
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

            rendered = FlowChat::Instagram::Renderer.new(prompt, choices: transformed).render
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

        # Instagram differs from Messenger/WhatsApp here: always_number?
        # forces a number into the body regardless of title ambiguity, so a
        # typed position resolves even on this unambiguous, unprefixed quick
        # reply rung - unlike test_round_trip_unambiguous_quick_reply_rung_
        # has_no_position on Messenger, where the equivalent digit is free
        # text. The quick reply's own title is still unprefixed either way;
        # always_number? only ever governs the body listing.
        def test_unambiguous_quick_reply_rung_still_accepts_a_typed_position
          choices = {"a" => "Alpha", "b" => "Beta"}
          @app.expect :call, [:prompt, "Pick", choices, nil], [@context]
          _, prompt, transformed, _ = @middleware.call(@context)

          rendered = FlowChat::Instagram::Renderer.new(prompt, choices: transformed).render
          assert_equal "Beta", rendered[2][:quick_replies][1][:title], "an unambiguous title is not prefixed"

          @context.input = "2"
          @app.expect :call, [:text, "response", nil, nil], [@context]
          @middleware.call(@context)

          assert_equal "b", @context.input,
            "always_number? puts a number in the body regardless of title ambiguity, so it must resolve"
          @app.verify
        end

        # On the numbered rung (above the carousel capacity) there is no
        # tappable surface and no separate title to alias, only the position
        # printed in the body; the round trip there is pulling that number
        # back out of the rendered body and typing it back.
        def test_round_trip_numbered_body_position_resolves
          choices = (1..31).to_h { |i| ["k#{i}", "Option #{i}"] }
          @app.expect :call, [:prompt, "Pick", choices, nil], [@context]

          _, prompt, transformed, _ = @middleware.call(@context)

          rendered = FlowChat::Instagram::Renderer.new(prompt, choices: transformed).render
          third_numbered_line = rendered[1].lines.grep(/^\d+\. /)[2]
          typed_position = third_numbered_line[/^\d+/]

          @context.input = typed_position
          @app.expect :call, [:text, "response", nil, nil], [@context]
          @middleware.call(@context)

          assert_equal "k3", @context.input
          @app.verify
        end

        def test_typed_number_resolves_on_the_carousel_rung
          choices = (1..14).to_h { |i| ["k#{i}", "Option #{i}"] }
          @app.expect :call, [:prompt, "Pick", choices, nil], [@context]

          @middleware.call(@context)

          @context.input = "3"
          @app.expect :call, [:text, "response", nil, nil], [@context]

          @middleware.call(@context)

          assert_equal "k3", @context.input
          @app.verify
        end

        # A generated id and a position occupy the same key space, so ids
        # must be resolved first. See the equivalent Messenger test for the
        # full mechanism; the risk is higher here because the position map
        # is live at every rung, not only above the carousel capacity.
        def test_generated_ids_win_over_positions
          choices = {"special" => "5"}.merge((1..4).to_h { |i| ["k#{i}", "Option #{i}"] })
          @app.expect :call, [:prompt, "Pick", choices, nil], [@context]

          @middleware.call(@context)

          assert_equal "k4", @session.get("instagram.position_mapping")["5"],
            "test setup assumption: position 5 is the choice \"k4\""

          @context.input = "5"
          @app.expect :call, [:text, "response", nil, nil], [@context]

          @middleware.call(@context)

          assert_equal "special", @context.input, "the id for the label \"5\" must win over position 5"
          @app.verify
        end

        # The always-on position map raises the stakes for the WhatsApp
        # clearing bug (Task 6) and its Messenger mirror (Task 13): on
        # Instagram a position map exists after EVERY menu, not only above
        # the carousel capacity, so a mapper that fails to clear it hijacks
        # every typed digit on every screen that follows a menu, not just
        # some of them.
        def test_stale_maps_do_not_hijack_a_later_free_text_digit
          choices = {"a" => "Alpha", "b" => "Beta"}
          @app.expect :call, [:prompt, "Pick", choices, nil], [@context]

          @middleware.call(@context)

          @context.input = "2"
          @app.expect :call, [:prompt, "How many bags?", nil, nil], [@context]

          @middleware.call(@context)

          assert_equal "b", @context.input

          @context.input = "2"
          @app.expect :call, [:text, "response", nil, nil], [@context]

          @middleware.call(@context)

          assert_equal "2", @context.input,
            "a typed digit on a screen with no choices must stay the digit, " \
            "but a stale mapping rewrote it to #{@context.input.inspect}"
          @app.verify
        end

        def test_gateway_exposes_the_instagram_hooks
          config = FlowChat::Instagram::Configuration.new(nil)
          config.page_id = "page_1"
          config.access_token = "tok"
          config.verify_token = "verify"

          gateway = FlowChat::Instagram::Gateway::SendApi.new(proc {}, config)

          assert_equal :instagram, gateway.platform
          assert_equal :instagram_send_api, gateway.gateway_name
          assert_equal FlowChat::Instagram::Renderer, gateway.renderer_class
          assert_equal FlowChat::Instagram::Middleware::ChoiceMapper,
            FlowChat::Instagram::Gateway::SendApi.choice_mapper_class
        end

        # Mock classes for testing, mirroring
        # test/unit/messenger/middleware/choice_mapper_test.rb.
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

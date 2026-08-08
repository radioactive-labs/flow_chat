# frozen_string_literal: true

# Module: ConsumeTurnTest
#
# Purpose:
# Tests FlowChat::App#consume_turn!, which lets a flow that reads the inbound
# outside the screen system declare that the message is spent.
#
# Why it exists:
# A flow can consume the turn itself, most often to route on the opening message
# before any screen runs. FlowChat cannot see that read. Left unsaid, #screen
# hands the same message to the first prompt the run reaches, so that prompt is
# answered without ever being asked and its message is never delivered. The flow
# then runs off its end, which the executor reports as "Unexpected end of flow.".
#
# What it does:
# - marks the turn consumed, so later screens prompt rather than consume
# - records the first-message marker #screen would have written, so the gate it
#   guards does not fire a turn late and swallow the customer's next message
# - leaves text and attachments readable, unlike #clear_turn!, which discards
#   them because a restart rebuilds the App from the context
#
# Contrast with #clear_turn!:
# clear_turn! serves go_back, where a RestartFlow rebuilds the App and the turn
# must not survive. consume_turn! keeps the turn and gives up only the right to
# answer a screen with it.

require "test_helper"

class ConsumeTurnTest < Minitest::Test
  def setup
    @context = FlowChat::Context.new
    @context.session = create_test_session_store
    @context["request.platform"] = :whatsapp
    @context.input = "I want to see a demo"
  end

  def test_returns_the_turn
    app = FlowChat::App.new(@context)

    taken = app.consume_turn!

    assert_equal "I want to see a demo", taken.to_s
  end

  def test_a_later_screen_prompts_instead_of_consuming_the_taken_turn
    app = FlowChat::App.new(@context)
    app.consume_turn!

    assert_raises(FlowChat::Interrupt::Prompt) do
      app.screen(:greeting) { |prompt| prompt.ask("How can we help?") }
    end
  end

  def test_without_it_the_screen_consumes_the_turn
    app = FlowChat::App.new(@context)
    @context.session.set(FlowChat::Input::START, "an earlier message")

    value = app.screen(:greeting) { |prompt| prompt.ask("How can we help?") }

    assert_equal "I want to see a demo", value,
      "this is the behaviour consume_turn! exists to prevent"
  end

  def test_records_the_first_message_marker
    app = FlowChat::App.new(@context)

    app.consume_turn!

    assert_equal "I want to see a demo", app.session.get(FlowChat::Input::START)
  end

  def test_leaves_an_existing_marker_alone
    @context.session.set(FlowChat::Input::START, "the real opener")
    app = FlowChat::App.new(@context)

    app.consume_turn!

    assert_equal "the real opener", app.session.get(FlowChat::Input::START)
  end

  def test_the_customers_next_message_answers_the_prompt_it_was_asked_for
    # The marker matters on the turn after. Without it the gate fires late and
    # takes the reply as though it were the opener, handing the screen nothing.
    app = FlowChat::App.new(@context)
    app.consume_turn!
    assert_raises(FlowChat::Interrupt::Prompt) do
      app.screen(:greeting) { |prompt| prompt.ask("How can we help?") }
    end

    next_context = FlowChat::Context.new
    next_context.session = @context.session
    next_context["request.platform"] = :whatsapp
    next_context.input = "yes please"
    next_app = FlowChat::App.new(next_context)

    answer = next_app.screen(:greeting) { |prompt| prompt.ask("How can we help?") }

    assert_equal "yes please", answer
  end

  def test_keeps_the_attachment_readable
    @context.input = ""
    @context["request.media"] = [{type: :image, url: "https://example.com/a.png"}]
    app = FlowChat::App.new(@context)

    app.consume_turn!

    assert_equal 1, app.media.size, "the turn is spent, not discarded"
    refute_nil @context["request.media"], "and the context keeps it too"
  end

  def test_an_attachment_opener_no_longer_answers_the_first_prompt
    @context.input = ""
    @context["request.media"] = [{type: :image, url: "https://example.com/a.png"}]
    app = FlowChat::App.new(@context)
    app.consume_turn!

    assert_raises(FlowChat::Interrupt::Prompt) do
      app.screen(:greeting) { |prompt| prompt.ask("How can we help?") }
    end
  end

  def test_ussd_does_not_use_the_first_message_marker
    @context["request.platform"] = :ussd
    app = FlowChat::App.new(@context)

    app.consume_turn!

    assert_nil app.session.get(FlowChat::Input::START)
  end
end

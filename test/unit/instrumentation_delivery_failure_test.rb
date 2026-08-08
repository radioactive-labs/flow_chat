# frozen_string_literal: true

# Module: InstrumentationDeliveryFailureTest
#
# Purpose:
# Tests Instrumentation#report_delivery_failure, which reports a reply the
# platform would not take.
#
# Why it exists:
# A gateway sends after the middleware stack has returned. An app that records
# what the flow said has therefore already recorded it, and recorded it as
# having gone out, before anything knows whether it did. Nothing downstream of
# the send can correct that, and the send is the only place that learns of the
# failure.
#
# Two readers, told differently:
# - the event is a broadcast, shaped like the gateway's own MESSAGE_SENT, so a
#   tool that writes whatever it is handed into a log learns nothing the send
#   did not already announce
# - the callback is the app that owns the turn, so it gets the context and can
#   reach the record it wrote
#
# Both are re-entrant on failure: neither may replace the delivery error with
# one of its own, which would hide the failure they are being told about.

require "test_helper"

class InstrumentationDeliveryFailureTest < Minitest::Test
  EVENT = "#{FlowChat::Instrumentation::Events::MESSAGE_DELIVERY_FAILED}.flow_chat"

  class Sender
    include FlowChat::Instrumentation

    def deliver(context, **payload, &block)
      report_delivery_failure(context, **payload, &block)
    end
  end

  def setup
    @context = FlowChat::Context.new
    @context["request.id"] = "chat-1"
    @sender = Sender.new
    @subscribers = []
    @original_callback = FlowChat::Config.on_delivery_failure
  end

  def teardown
    @subscribers.each { |s| ActiveSupport::Notifications.unsubscribe(s) }
    FlowChat::Config.on_delivery_failure = @original_callback
  end

  def on_failure(&block)
    @subscribers << ActiveSupport::Notifications.subscribe(EVENT) do |*args|
      block.call(ActiveSupport::Notifications::Event.new(*args).payload)
    end
  end

  def test_returns_what_the_delivery_returned
    on_failure { flunk "should not be reported" }
    FlowChat::Config.on_delivery_failure = ->(_c, _e) { flunk "should not be called" }

    assert_equal :sent, @sender.deliver(@context) { :sent }
  end

  def test_the_event_carries_the_send_and_the_error
    seen = nil
    on_failure { |payload| seen = payload }

    error = assert_raises(RuntimeError) do
      @sender.deliver(@context, to: "chat-1", platform: :telegram) { raise "telegram said 401" }
    end

    assert_equal "chat-1", seen[:to]
    assert_equal :telegram, seen[:platform]
    assert_equal "RuntimeError", seen[:error_class]
    assert_equal "telegram said 401", seen[:message]
    assert_equal "telegram said 401", error.message
  end

  # The context holds the gateway client and the raw inbound body, so it holds
  # the platform credentials. Anyone may subscribe, including tools that write
  # whatever they are handed straight into a log.
  def test_the_event_carries_nothing_from_the_context
    @context["telegram.client"] = "a client holding the bot token"
    @context["request.body"] = {"secret" => "the raw webhook"}
    seen = nil
    on_failure { |payload| seen = payload }

    assert_raises(RuntimeError) { @sender.deliver(@context) { raise "boom" } }

    refute seen.key?(:context)
    written = seen.values.join(" ")
    refute_includes written, "bot token"
    refute_includes written, "raw webhook"
  end

  # The app is what knows which record to mark, and it reaches that through
  # what it put on the context during the turn.
  def test_the_callback_gets_the_context_and_the_error
    @context["app.bot_message_id"] = 42
    seen = nil
    FlowChat::Config.on_delivery_failure = ->(context, error) { seen = [context["app.bot_message_id"], error] }

    assert_raises(RuntimeError) { @sender.deliver(@context) { raise "boom" } }

    assert_equal 42, seen[0]
    assert_equal "boom", seen[1].message
  end

  # Marking the message and alerting on the broken connection are two jobs for
  # one failure, and neither is the other's to do.
  def test_every_subscriber_hears_it_alongside_the_callback
    heard = []
    on_failure { heard << :subscriber_one }
    on_failure { heard << :subscriber_two }
    FlowChat::Config.on_delivery_failure = ->(_c, _e) { heard << :app }

    assert_raises(RuntimeError) { @sender.deliver(@context) { raise "boom" } }

    assert_equal [:subscriber_one, :subscriber_two, :app], heard
  end

  def test_a_delivery_error_still_raises_with_nobody_listening
    FlowChat::Config.on_delivery_failure = nil

    assert_raises(RuntimeError) { @sender.deliver(@context) { raise "boom" } }
  end

  # Losing the delivery error to a fault in the reporting would hide the very
  # failure this exists to report.
  def test_a_subscriber_that_raises_does_not_replace_the_delivery_error
    on_failure { raise ArgumentError, "subscriber is broken" }

    error = assert_raises(RuntimeError) do
      @sender.deliver(@context) { raise "telegram said 401" }
    end

    assert_equal "telegram said 401", error.message
  end

  def test_a_callback_that_raises_does_not_replace_the_delivery_error
    FlowChat::Config.on_delivery_failure = ->(_c, _e) { raise ArgumentError, "callback is broken" }

    error = assert_raises(RuntimeError) do
      @sender.deliver(@context) { raise "telegram said 401" }
    end

    assert_equal "telegram said 401", error.message
  end

  # A subscriber blowing up must not stop the app hearing about the failure.
  def test_the_callback_still_runs_after_a_subscriber_raises
    on_failure { raise ArgumentError, "subscriber is broken" }
    called = false
    FlowChat::Config.on_delivery_failure = ->(_c, _e) { called = true }

    assert_raises(RuntimeError) { @sender.deliver(@context) { raise "boom" } }

    assert called
  end
end

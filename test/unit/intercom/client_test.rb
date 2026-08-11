# frozen_string_literal: true

require "test_helper"
require "webmock/minitest"

class FlowChat::Intercom::ClientTest < Minitest::Test
  def setup
    @config = FlowChat::Intercom::Configuration.new("test")
    @config.access_token = "test_access_token"
    @config.admin_id = "test_admin_id"

    @client = FlowChat::Intercom::Client.new(@config)
    @client.app_id = "test_app_id"  # Normally set by gateway from request body

    WebMock.enable!
    WebMock.reset!
  end

  def teardown
    WebMock.disable!
    WebMock.reset!
  end

  # ============================================================================
  # HTML PARSING TESTS - Class Method
  # ============================================================================

  def test_parse_html_simple_text
    assert_equal "Hello world", FlowChat::Intercom::Client.parse_html("Hello world")
  end

  def test_parse_html_paragraph
    assert_equal "Hello world", FlowChat::Intercom::Client.parse_html("<p>Hello world</p>")
  end

  def test_parse_html_bold
    assert_equal "Hello **world**", FlowChat::Intercom::Client.parse_html("<p>Hello <strong>world</strong></p>")
  end

  def test_parse_html_italic
    assert_equal "Hello _world_", FlowChat::Intercom::Client.parse_html("<p>Hello <em>world</em></p>")
  end

  def test_parse_html_link
    assert_equal "[click here](https://example.com)", FlowChat::Intercom::Client.parse_html('<a href="https://example.com">click here</a>')
  end

  def test_parse_html_line_breaks
    result = FlowChat::Intercom::Client.parse_html("Hello<br>world")
    assert_includes result, "Hello"
    assert_includes result, "world"
  end

  def test_parse_html_unordered_list
    html = "<ul><li>Item 1</li><li>Item 2</li></ul>"
    result = FlowChat::Intercom::Client.parse_html(html)
    assert_includes result, "Item 1"
    assert_includes result, "Item 2"
  end

  def test_parse_html_ordered_list
    html = "<ol><li>First</li><li>Second</li></ol>"
    result = FlowChat::Intercom::Client.parse_html(html)
    assert_includes result, "First"
    assert_includes result, "Second"
  end

  def test_parse_html_inline_code
    assert_equal "Use `code` here", FlowChat::Intercom::Client.parse_html("<p>Use <code>code</code> here</p>")
  end

  def test_parse_html_nested_formatting
    html = "<p>This is <strong>bold and <em>italic</em></strong> text</p>"
    result = FlowChat::Intercom::Client.parse_html(html)
    assert_includes result, "**"
    assert_includes result, "*"
    assert_includes result, "bold"
    assert_includes result, "italic"
  end

  def test_parse_html_nil_returns_empty_string
    assert_equal "", FlowChat::Intercom::Client.parse_html(nil)
  end

  def test_parse_html_empty_string_returns_empty_string
    assert_equal "", FlowChat::Intercom::Client.parse_html("")
  end

  def test_parse_html_whitespace_only_returns_empty_string
    assert_equal "", FlowChat::Intercom::Client.parse_html("   ")
  end

  def test_parse_html_strips_whitespace
    result = FlowChat::Intercom::Client.parse_html("  <p>Hello</p>  ")
    assert_equal "Hello", result
  end

  def test_parse_html_complex_intercom_message
    html = "<p>Hi there! I need help with <strong>my account</strong>.</p><p>Can you assist?</p>"
    result = FlowChat::Intercom::Client.parse_html(html)
    assert_includes result, "Hi there!"
    assert_includes result, "**my account**"
    assert_includes result, "Can you assist?"
  end

  # ============================================================================
  # HTML PARSING TESTS - Instance Method
  # ============================================================================

  def test_parse_message_simple_text
    assert_equal "Hello world", @client.parse_message("Hello world")
  end

  def test_parse_message_with_html
    assert_equal "Hello **world**", @client.parse_message("<p>Hello <strong>world</strong></p>")
  end

  def test_parse_message_nil_returns_empty_string
    assert_equal "", @client.parse_message(nil)
  end

  def test_parse_message_empty_returns_empty_string
    assert_equal "", @client.parse_message("")
  end

  def test_parse_message_delegates_to_class_method
    html = "<p>Test <em>message</em></p>"
    assert_equal FlowChat::Intercom::Client.parse_html(html), @client.parse_message(html)
  end

  # ============================================================================
  # ERROR REPORTING TESTS
  # ============================================================================

  def test_authentication_error_instruments_api_error_event
    # Stub the intercom gem to raise authentication error
    @client.intercom.stub(:conversations, ->(*) { raise ::Intercom::AuthenticationError.new("Invalid token") }) do
      events = []
      ActiveSupport::Notifications.subscribe("api.error.flow_chat") do |event|
        events << event
      end

      assert_raises(FlowChat::Intercom::ConfigurationError) do
        @client.send_message("conv_123", "Hello")
      end

      assert_equal 1, events.size

      event = events.first
      assert_equal :intercom, event.payload[:platform]
      assert_equal "test_app_id", event.payload[:app_id]
      assert_equal "conv_123", event.payload[:conversation_id]
      assert_equal "test_admin_id", event.payload[:admin_id]
      assert_includes event.payload[:message], "authentication failed"
    ensure
      ActiveSupport::Notifications.unsubscribe("api.error.flow_chat")
    end
  end

  def test_server_error_instruments_api_error_event
    @client.intercom.stub(:conversations, ->(*) { raise ::Intercom::ServerError.new("Internal error") }) do
      events = []
      ActiveSupport::Notifications.subscribe("api.error.flow_chat") do |event|
        events << event
      end

      result = @client.send_message("conv_456", "Hello")

      assert_nil result
      assert_equal 1, events.size

      event = events.first
      assert_equal :intercom, event.payload[:platform]
      assert_equal "conv_456", event.payload[:conversation_id]
      assert_includes event.payload[:message], "server error"
    ensure
      ActiveSupport::Notifications.unsubscribe("api.error.flow_chat")
    end
  end

  def test_generic_exception_instruments_api_error_event
    @client.intercom.stub(:conversations, ->(*) { raise StandardError.new("Something went wrong") }) do
      events = []
      ActiveSupport::Notifications.subscribe("api.error.flow_chat") do |event|
        events << event
      end

      result = @client.send_message("conv_789", "Hello")

      assert_nil result
      assert_equal 1, events.size

      event = events.first
      assert_equal :intercom, event.payload[:platform]
      assert_equal "conv_789", event.payload[:conversation_id]
      assert_includes event.payload[:message], "StandardError"
    ensure
      ActiveSupport::Notifications.unsubscribe("api.error.flow_chat")
    end
  end

  # A subscriber deciding what to do about a failure reads the structured keys.
  # Matching on the message would break the moment someone rewords a log line.

  def test_authentication_error_is_typed_and_carries_its_http_code
    error = ::Intercom::AuthenticationError.new("Invalid token", http_code: 401)

    @client.intercom.stub(:conversations, ->(*) { raise error }) do
      events = []
      ActiveSupport::Notifications.subscribe("api.error.flow_chat") { |e| events << e }

      assert_raises(FlowChat::Intercom::ConfigurationError) do
        @client.send_message("conv_123", "Hello")
      end

      payload = events.first.payload
      assert_equal "authentication", payload[:error_type]
      assert_equal 401, payload[:error_code]
      assert_equal "Intercom::AuthenticationError", payload[:error_class]
    ensure
      ActiveSupport::Notifications.unsubscribe("api.error.flow_chat")
    end
  end

  def test_resource_not_found_is_typed
    error = ::Intercom::ResourceNotFound.new("Conversation not found", http_code: 404)

    @client.intercom.stub(:conversations, ->(*) { raise error }) do
      events = []
      ActiveSupport::Notifications.subscribe("api.error.flow_chat") { |e| events << e }

      @client.send_message("conv_missing", "Hello")

      payload = events.first.payload
      assert_equal "resource_not_found", payload[:error_type]
      assert_equal 404, payload[:error_code]
    ensure
      ActiveSupport::Notifications.unsubscribe("api.error.flow_chat")
    end
  end

  def test_server_error_is_typed
    error = ::Intercom::ServerError.new("Internal error", http_code: 500)

    @client.intercom.stub(:conversations, ->(*) { raise error }) do
      events = []
      ActiveSupport::Notifications.subscribe("api.error.flow_chat") { |e| events << e }

      @client.send_message("conv_456", "Hello")

      payload = events.first.payload
      assert_equal "server_error", payload[:error_type]
      assert_equal 500, payload[:error_code]
    ensure
      ActiveSupport::Notifications.unsubscribe("api.error.flow_chat")
    end
  end

  def test_a_non_intercom_exception_is_classified_by_its_class
    @client.intercom.stub(:conversations, ->(*) { raise ArgumentError.new("bad input") }) do
      events = []
      ActiveSupport::Notifications.subscribe("api.error.flow_chat") { |e| events << e }

      @client.send_message("conv_789", "Hello")

      payload = events.first.payload
      assert_equal "ArgumentError", payload[:error_class]
      assert_nil payload[:error_type], "only a failure Intercom names gets a type"
      assert_nil payload[:error_code]
    ensure
      ActiveSupport::Notifications.unsubscribe("api.error.flow_chat")
    end
  end

  def test_resource_not_found_instruments_api_error_event
    @client.intercom.stub(:conversations, ->(*) { raise ::Intercom::ResourceNotFound.new("Conversation not found") }) do
      events = []
      ActiveSupport::Notifications.subscribe("api.error.flow_chat") do |event|
        events << event
      end

      result = @client.send_message("conv_not_found", "Hello")

      assert_nil result
      assert_equal 1, events.size

      event = events.first
      assert_equal :intercom, event.payload[:platform]
      assert_equal "conv_not_found", event.payload[:conversation_id]
      assert_includes event.payload[:message], "not found"
    ensure
      ActiveSupport::Notifications.unsubscribe("api.error.flow_chat")
    end
  end

  def test_rate_limit_does_not_instrument_api_error_event
    @client.intercom.stub(:conversations, ->(*) { raise ::Intercom::RateLimitExceeded.new("Too many requests") }) do
      events = []
      ActiveSupport::Notifications.subscribe("api.error.flow_chat") do |event|
        events << event
      end

      assert_raises(FlowChat::Intercom::RateLimitError) do
        @client.send_message("conv_rate_limited", "Hello")
      end

      # Rate limits are expected and handled differently - no api.error instrumentation
      assert_equal 0, events.size
    ensure
      ActiveSupport::Notifications.unsubscribe("api.error.flow_chat")
    end
  end

  # ============================================================================
  # OUTBOUND MEDIA TESTS
  # ============================================================================

  def test_send_message_forwards_attachment_urls_for_image_media
    stub_request(:post, "https://api.intercom.io/conversations/conv_media/reply").to_return(
      status: 200,
      body: {"type" => "conversation", "id" => "msg_1"}.to_json,
      headers: {"Content-Type" => "application/json"}
    )

    @client.send_message("conv_media", "Check this out", media: {type: "image", url: "https://example.com/photo.jpg"})

    assert_requested :post, "https://api.intercom.io/conversations/conv_media/reply" do |req|
      body = JSON.parse(req.body)
      body["attachment_urls"] == ["https://example.com/photo.jpg"]
    end
  end

  def test_send_message_omits_attachment_urls_when_no_media
    stub_request(:post, "https://api.intercom.io/conversations/conv_plain/reply").to_return(
      status: 200,
      body: {"type" => "conversation", "id" => "msg_2"}.to_json,
      headers: {"Content-Type" => "application/json"}
    )

    @client.send_message("conv_plain", "Hello there")

    assert_requested :post, "https://api.intercom.io/conversations/conv_plain/reply" do |req|
      body = JSON.parse(req.body)
      !body.key?("attachment_urls")
    end
  end

  def test_plain_text_send_is_byte_for_byte_unchanged
    stub_request(:post, "https://api.intercom.io/conversations/conv_text/reply").to_return(
      status: 200,
      body: {"type" => "conversation", "id" => "msg_3"}.to_json,
      headers: {"Content-Type" => "application/json"}
    )

    @client.send_message("conv_text", "Hello there")

    assert_requested :post, "https://api.intercom.io/conversations/conv_text/reply" do |req|
      body = JSON.parse(req.body)
      body == {
        "type" => "admin",
        "admin_id" => "test_admin_id",
        "message_type" => "comment",
        "body" => "<p>Hello there</p>",
        "conversation_id" => "conv_text"
      }
    end
  end

  def test_build_reply_payload_includes_attachment_urls_for_image_media
    response = [:text, "<p>Look</p>", {attachment_urls: ["https://example.com/photo.jpg"]}]

    payload = @client.build_reply_payload(response, "conv_sim")

    assert_equal ["https://example.com/photo.jpg"], payload[:attachment_urls]
  end

  def test_build_reply_payload_omits_attachment_urls_when_absent
    response = [:text, "<p>Look</p>", {}]

    payload = @client.build_reply_payload(response, "conv_sim")

    refute payload.key?(:attachment_urls)
  end

  # ============================================================================
  # QUICK REPLY (CHOICE SCREEN) TESTS
  # ============================================================================

  def test_choice_screen_sends_two_replies_comment_then_quick_reply
    sent = []
    stub_request(:post, "https://api.intercom.io/conversations/conv_choice/reply").to_return do |request|
      sent << JSON.parse(request.body)
      {status: 200, body: {"type" => "conversation", "id" => "msg_#{sent.size}"}.to_json, headers: {"Content-Type" => "application/json"}}
    end

    choices = {"sales" => "Sales", "support" => "Support"}
    result = @client.send_message("conv_choice", "Which one?", choices: choices)

    assert_equal 2, sent.size
    comment, quick_reply = sent

    assert_equal "comment", comment["message_type"]
    assert_includes comment["body"], "Which one?"
    refute comment.key?("reply_options")

    assert_equal "quick_reply", quick_reply["message_type"]
    assert_equal "admin", quick_reply["type"]
    assert_equal "test_admin_id", quick_reply["admin_id"]
    assert_equal(
      [{"uuid" => "sales", "text" => "Sales"}, {"uuid" => "support", "text" => "Support"}],
      quick_reply["reply_options"]
    )
    assert_equal %w[message_type type admin_id reply_options conversation_id].sort, quick_reply.keys.sort
    refute quick_reply.key?("body")

    # The result returned is the last call's - the quick_reply's - response.
    assert_equal "msg_2", result["id"]
  end

  def test_choice_screen_with_media_puts_attachment_urls_on_comment_not_quick_reply
    sent = []
    stub_request(:post, "https://api.intercom.io/conversations/conv_choice_media/reply").to_return do |request|
      sent << JSON.parse(request.body)
      {status: 200, body: {"type" => "conversation", "id" => "msg_#{sent.size}"}.to_json, headers: {"Content-Type" => "application/json"}}
    end

    choices = {"yes" => "Yes", "no" => "No"}
    media = {type: "image", url: "https://example.com/photo.jpg"}
    @client.send_message("conv_choice_media", "Well?", choices: choices, media: media)

    comment, quick_reply = sent

    assert_equal ["https://example.com/photo.jpg"], comment["attachment_urls"]
    refute quick_reply.key?("attachment_urls")
  end

  def test_plain_text_screen_still_sends_exactly_one_reply
    stub_request(:post, "https://api.intercom.io/conversations/conv_one/reply").to_return(
      status: 200,
      body: {"type" => "conversation", "id" => "msg_one"}.to_json,
      headers: {"Content-Type" => "application/json"}
    )

    @client.send_message("conv_one", "Just text, no choices")

    assert_requested :post, "https://api.intercom.io/conversations/conv_one/reply", times: 1
  end
end

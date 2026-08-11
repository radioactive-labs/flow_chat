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
      payload && payload["template_type"] == "generic" && payload["elements"].length == 5
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

  # Meta's HUMAN_AGENT tag extends the free-form send window to 7 days. The
  # tag replaces messaging_type: "RESPONSE" rather than riding alongside it.
  def test_tagged_send_sets_message_tag_and_never_response
    @client.send_message("psid_1", "Hello", tag: "HUMAN_AGENT")

    assert_requested(:post, @config.messages_url) do |req|
      body = JSON.parse(req.body)
      body["messaging_type"] == "MESSAGE_TAG" && body["tag"] == "HUMAN_AGENT"
    end
  end

  def test_untagged_send_is_byte_for_byte_unchanged
    @client.send_message("psid_1", "Hello")

    assert_requested(:post, @config.messages_url) do |req|
      body = JSON.parse(req.body)
      body == {"recipient" => {"id" => "psid_1"}, "message" => {"text" => "Hello"}, "messaging_type" => "RESPONSE"}
    end
  end

  def test_send_text_passes_the_tag_through
    @client.send_text("psid_1", "Hello", tag: "HUMAN_AGENT")

    assert_requested(:post, @config.messages_url) do |req|
      JSON.parse(req.body)["tag"] == "HUMAN_AGENT"
    end
  end

  # The easy place to get this wrong: tagging only the first chunk of a
  # split reply would leave the remaining parts sent untagged, refused
  # outside the free-form window while the first part goes through.
  def test_every_part_of_a_split_text_carries_the_tag
    long = "word " * 600 # comfortably over 2000 characters, splits into 2 sends

    @client.send_message("psid_1", long, tag: "HUMAN_AGENT")

    assert_requested(:post, @config.messages_url, times: 2) do |req|
      JSON.parse(req.body)["tag"] == "HUMAN_AGENT"
    end
  end

  # Same failure mode as the split-text case, but on the quick-replies path:
  # the chunk carrying the question and the quick replies is not the only
  # chunk sent when the body itself needed splitting.
  def test_every_part_of_a_split_quick_reply_send_carries_the_tag
    long = "word " * 600
    choices = {"a" => "Alpha", "b" => "Beta"}

    @client.send_message("psid_1", long, choices: choices, tag: "HUMAN_AGENT")

    assert_requested(:post, @config.messages_url, times: 2) do |req|
      JSON.parse(req.body)["tag"] == "HUMAN_AGENT"
    end
  end
end

require "test_helper"
require "webmock/minitest"

class InstagramClientTest < Minitest::Test
  def setup
    @config = FlowChat::Instagram::Configuration.new(nil)
    @config.page_id = "page_1"
    @config.access_token = "tok"
    @config.verify_token = "verify"
    @client = FlowChat::Instagram::Client.new(@config)

    WebMock.enable!
    WebMock.reset!
    stub_request(:post, @config.messages_url)
      .to_return(status: 200, body: {"recipient_id" => "igsid_1", "message_id" => "mid.1"}.to_json)
  end

  def teardown
    WebMock.disable!
    WebMock.reset!
  end

  def test_sends_text_with_the_send_api_shape
    result = @client.send_message("igsid_1", "Hello")

    assert_equal "mid.1", result["message_id"]
    assert_requested(:post, @config.messages_url) do |req|
      body = JSON.parse(req.body)
      body["recipient"] == {"id" => "igsid_1"} &&
        body["message"] == {"text" => "Hello"}
    end
  end

  # Messenger documents messaging_type as required on a send. Meta's Instagram
  # reference documents recipient and message only, so inheriting Messenger's
  # would put an undocumented parameter on every Instagram send.
  def test_omits_messaging_type_which_instagram_does_not_document
    @client.send_message("igsid_1", "Hello")

    assert_requested(:post, @config.messages_url) do |req|
      !JSON.parse(req.body).key?("messaging_type")
    end
  end

  def test_quick_replies_ride_on_the_text_message
    @client.send_message("igsid_1", "Pick", choices: {"a" => "Alpha", "b" => "Beta"})

    assert_requested(:post, @config.messages_url) do |req|
      message = JSON.parse(req.body)["message"]
      message["text"].include?("Pick") && message["quick_replies"].length == 2
    end
  end

  def test_carousel_posts_a_generic_template
    choices = (1..14).to_h { |i| ["k#{i}", "Option #{i}"] }

    @client.send_message("igsid_1", "Pick", choices: choices)

    assert_requested(:post, @config.messages_url) do |req|
      payload = JSON.parse(req.body).dig("message", "attachment", "payload")
      payload && payload["template_type"] == "generic" && payload["elements"].length == 5
    end
  end

  def test_long_text_is_split_into_several_sends
    long = "word " * 300 # comfortably over the 1000 byte cap

    @client.send_message("igsid_1", long)

    assert_requested(:post, @config.messages_url, times: 2)
  end

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

  def test_failed_request_returns_nil
    WebMock.reset!
    stub_request(:post, @config.messages_url).to_return(status: 400, body: '{"error":{"message":"bad"}}')

    assert_nil @client.send_message("igsid_1", "Hello")
  end
end

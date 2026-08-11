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

  # The judgement call: Instagram overrides messaging_type? to false because
  # Meta never documented RESPONSE for Instagram, but Meta does document
  # MESSAGE_TAG with HUMAN_AGENT for Instagram. A tagged send must set the
  # field here even though an untagged send never does.
  def test_tagged_send_sets_message_tag_even_though_messaging_type_is_undocumented
    @client.send_message("igsid_1", "Hello", tag: "HUMAN_AGENT")

    assert_requested(:post, @config.messages_url) do |req|
      body = JSON.parse(req.body)
      body["messaging_type"] == "MESSAGE_TAG" && body["tag"] == "HUMAN_AGENT"
    end
  end

  def test_untagged_send_still_omits_messaging_type
    @client.send_message("igsid_1", "Hello")

    assert_requested(:post, @config.messages_url) do |req|
      body = JSON.parse(req.body)
      !body.key?("messaging_type") && !body.key?("tag")
    end
  end

  def test_every_part_of_a_split_text_carries_the_tag
    long = "word " * 300 # comfortably over the 1000 byte cap, splits into 2 sends

    @client.send_message("igsid_1", long, tag: "HUMAN_AGENT")

    assert_requested(:post, @config.messages_url, times: 2) do |req|
      JSON.parse(req.body)["tag"] == "HUMAN_AGENT"
    end
  end

  # Media used to be silently dropped whenever choices were also present.
  def test_media_with_choices_posts_media_then_quick_replies
    calls = []
    stub_request(:post, @config.messages_url).to_return do |req|
      calls << JSON.parse(req.body)["message"]
      {status: 200, body: {"message_id" => "mid.1"}.to_json}
    end

    media = {type: :image, url: "https://example.com/a.png"}
    @client.send_message("igsid_1", "Pick", choices: {"a" => "Alpha", "b" => "Beta"}, media: media)

    assert_equal 2, calls.length
    assert_equal "image", calls[0]["attachment"]["type"]
    assert calls[1].key?("quick_replies")
    # Instagram's interactive surfaces render on mobile only, so the numbered
    # body must survive alongside the media, same as with no media at all.
    assert_includes calls[1]["text"], "1. Alpha"
  end

  def test_media_with_choices_carries_the_tag_on_every_part
    media = {type: :image, url: "https://example.com/a.png"}
    @client.send_message("igsid_1", "Pick", choices: {"a" => "Alpha", "b" => "Beta"}, media: media, tag: "HUMAN_AGENT")

    assert_requested(:post, @config.messages_url, times: 2) do |req|
      JSON.parse(req.body)["tag"] == "HUMAN_AGENT"
    end
  end
end

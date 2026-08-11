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

  # A single token with no whitespace inside it to split on (a long URL,
  # most often) used to ride through whole, over cap, since the whitespace
  # splitter has no smaller boundary to break it on.
  def test_a_single_oversized_token_is_hard_split
    long_token = "a" * 2500 # one word, no whitespace at all, over the 2000 char cap

    @client.send_message("psid_1", long_token)

    cap = FlowChat::Config.messenger.max_text_length
    assert_requested(:post, @config.messages_url, times: 2) do |req|
      JSON.parse(req.body)["message"]["text"].length <= cap
    end
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

  # Media used to be silently dropped whenever choices were also present,
  # because render() only ever built the attachment when choices were blank.

  def test_media_with_a_small_choice_set_posts_media_then_quick_replies
    calls = []
    stub_request(:post, @config.messages_url).to_return do |req|
      calls << JSON.parse(req.body)["message"]
      {status: 200, body: {"message_id" => "mid.1"}.to_json}
    end

    media = {type: :image, url: "https://example.com/a.png"}
    @client.send_message("psid_1", "Pick", choices: {"a" => "Alpha", "b" => "Beta"}, media: media)

    assert_equal 2, calls.length
    assert_equal "image", calls[0]["attachment"]["type"]
    assert_equal "https://example.com/a.png", calls[0]["attachment"]["payload"]["url"]
    assert calls[1].key?("quick_replies")
  end

  def test_media_with_a_mid_size_choice_set_posts_media_then_carousel
    calls = []
    stub_request(:post, @config.messages_url).to_return do |req|
      calls << JSON.parse(req.body)["message"]
      {status: 200, body: {"message_id" => "mid.1"}.to_json}
    end

    choices = (1..14).to_h { |i| ["k#{i}", "Option #{i}"] }
    media = {type: :image, url: "https://example.com/a.png"}
    @client.send_message("psid_1", "Pick", choices: choices, media: media)

    # Media, then the carousel's own caption text, then the carousel
    # attachment - the caption-then-attachment split is the carousel's
    # existing behaviour, unrelated to media.
    assert_equal 3, calls.length
    assert_equal "image", calls[0]["attachment"]["type"]
    assert_equal "generic", calls[2].dig("attachment", "payload", "template_type")
  end

  def test_media_above_the_carousel_cap_posts_media_then_numbered_text
    calls = []
    stub_request(:post, @config.messages_url).to_return do |req|
      calls << JSON.parse(req.body)["message"]
      {status: 200, body: {"message_id" => "mid.1"}.to_json}
    end

    choices = (1..31).to_h { |i| ["k#{i}", "Option #{i}"] }
    media = {type: :image, url: "https://example.com/a.png"}
    @client.send_message("psid_1", "Pick", choices: choices, media: media)

    assert_equal 2, calls.length
    assert_equal "image", calls[0]["attachment"]["type"]
    assert_includes calls[1]["text"], "31. Option 31"
  end

  # Every part of a media-plus-choices send is a place the tag can go
  # missing just as easily as on a split text reply.
  def test_media_with_choices_carries_the_tag_on_every_part
    media = {type: :image, url: "https://example.com/a.png"}
    @client.send_message("psid_1", "Pick", choices: {"a" => "Alpha", "b" => "Beta"}, media: media, tag: "HUMAN_AGENT")

    assert_requested(:post, @config.messages_url, times: 2) do |req|
      JSON.parse(req.body)["tag"] == "HUMAN_AGENT"
    end
  end
end

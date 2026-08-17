require "test_helper"
require "webmock/minitest"

class WhatsappIntegrationTest < Minitest::Test
  class GreetingFlow < FlowChat::Flow
    def main_page
      name = app.screen(:name) { |p| p.ask "What is your name?" }
      app.say "Hello, #{name}!"
    end
  end

  class ChoiceFlow < FlowChat::Flow
    def main_page
      choice = app.screen(:choice) do |p|
        p.select "Pick a color:", {"red" => "Red", "green" => "Green", "blue" => "Blue"}
      end
      app.say "You picked #{choice}!"
    end
  end

  class ListChoiceFlow < FlowChat::Flow
    def main_page
      choice = app.screen(:choice) do |p|
        p.select "Pick a fruit:", {
          "apple" => "Apple",
          "banana" => "Banana",
          "cherry" => "Cherry",
          "date" => "Date"
        }
      end
      app.say "You picked #{choice}!"
    end
  end

  class MediaFlow < FlowChat::Flow
    def main_page
      app.say "Here's an image", media: {type: :image, url: "https://example.com/photo.jpg"}
    end
  end

  class DocumentFlow < FlowChat::Flow
    def main_page
      app.say "Here's a document", media: {type: :document, url: "https://example.com/doc.pdf", filename: "report.pdf"}
    end
  end

  # Media plus more than 3 choices used to be unreachable: Prompt raised
  # ArgumentError before this ever reached a renderer (Blocker 1). 4 choices
  # is above WhatsApp's MAX_BUTTONS (3), so this lands on the interactive
  # list rung, with media forced out as its own message ahead of it (see
  # WhatsApp::Renderer#build_selection_message_with_media) - exactly the
  # combination the old guard made impossible to exercise end to end.
  class MediaChoiceFlow < FlowChat::Flow
    def main_page
      choice = app.screen(:plan) do |prompt|
        prompt.select "Choose a plan", {
          "basic" => "Basic Plan",
          "pro" => "Pro Plan",
          "team" => "Team Plan",
          "enterprise" => "Enterprise Plan"
        }, media: {type: :image, url: "https://example.com/plans.png"}
      end
      app.say "You picked #{choice}."
    end
  end

  # Array choices make key == label (see Prompt#normalize_choices), which is
  # what let a resolved choice collide with its own mapping key and defeat
  # should_clear_for_new_flow? (Blocker 3). Long, similar-prefixed labels
  # force FlowChat::ChoiceTitles to number them, so a plain "1" resolves via
  # the position map exactly as in the reported repro.
  class ArrayMenuThenPinFlow < FlowChat::Flow
    def main_page
      choice = app.screen(:choice) do |prompt|
        prompt.select "Choose one", [
          "A very long label that gets truncated for sure",
          "Another very long label here for sure too"
        ]
      end
      pin = app.screen(:pin) { |prompt| prompt.ask "Enter your PIN:" }
      app.say "You picked #{choice} and entered PIN #{pin}."
    end
  end

  def setup
    @config = FlowChat::Whatsapp::Configuration.new("test")
    @config.access_token = "test_access_token"
    @config.phone_number_id = "123456789"
    @config.verify_token = "test_verify_token"
    @config.app_secret = "test_app_secret"
    @config.skip_signature_validation = true

    WebMock.enable!
    WebMock.reset!

    # Stub all WhatsApp API calls
    @api_base_url = FlowChat::Config.whatsapp.api_base_url
    stub_request(:post, /graph\.facebook\.com/).to_return(
      status: 200,
      body: {"messages" => [{"id" => "wamid.test123"}]}.to_json
    )
  end

  def teardown
    WebMock.disable!
    WebMock.reset!
  end

  # ============================================================================
  # FULL FLOW INTEGRATION TESTS
  # ============================================================================

  def test_full_greeting_flow_prompts_for_name
    controller = create_whatsapp_controller(
      message: build_text_message(text: "Hi")
    )

    run_processor(controller, GreetingFlow)

    # Should send "What is your name?" prompt
    assert_requested :post, "#{@api_base_url}/123456789/messages" do |req|
      body = JSON.parse(req.body)
      body["type"] == "text" &&
        body["text"]["body"] == "What is your name?" &&
        body["to"] == "+256700123456"
    end
  end

  def test_full_greeting_flow_completes_with_name
    # Set up session with name already collected
    session_data = {"name" => "Alice"}

    controller = create_whatsapp_controller(
      message: build_text_message(text: "ignored")  # Input is ignored since name is in session
    )

    run_processor(controller, GreetingFlow, session_data: session_data)

    # Should send greeting
    assert_requested :post, "#{@api_base_url}/123456789/messages" do |req|
      body = JSON.parse(req.body)
      body["type"] == "text" &&
        body["text"]["body"] == "Hello, Alice!" &&
        body["to"] == "+256700123456"
    end
  end

  def test_choice_flow_shows_interactive_buttons
    controller = create_whatsapp_controller(
      message: build_text_message(text: "start")
    )

    run_processor(controller, ChoiceFlow)

    # Should send message with interactive buttons (3 or fewer choices)
    assert_requested :post, "#{@api_base_url}/123456789/messages" do |req|
      body = JSON.parse(req.body)
      body["type"] == "interactive" &&
        body["interactive"]["type"] == "button" &&
        body["interactive"]["body"]["text"] == "Pick a color:" &&
        body["interactive"]["action"]["buttons"].is_a?(Array) &&
        body["interactive"]["action"]["buttons"].length == 3
    end
  end

  def test_list_choice_flow_shows_interactive_list
    controller = create_whatsapp_controller(
      message: build_text_message(text: "start")
    )

    run_processor(controller, ListChoiceFlow)

    # Should send message with interactive list (more than 3 choices)
    assert_requested :post, "#{@api_base_url}/123456789/messages" do |req|
      body = JSON.parse(req.body)
      body["type"] == "interactive" &&
        body["interactive"]["type"] == "list" &&
        body["interactive"]["body"]["text"] == "Pick a fruit:" &&
        body["interactive"]["action"]["sections"].is_a?(Array)
    end
  end

  def test_choice_flow_button_reply_completes_flow
    # Set up session with:
    # - $start$ to indicate flow has been initialized (first input consumed)
    # - whatsapp.choice_mapping to have valid choice options
    session_data = {
      "$start$" => "start",
      "whatsapp.choice_mapping" => {"Green" => "green"}
    }

    controller = create_whatsapp_controller(
      message: build_button_reply(button_id: "Green")
    )

    run_processor(controller, ChoiceFlow, session_data: session_data)

    # Should send completion message
    assert_requested :post, "#{@api_base_url}/123456789/messages" do |req|
      body = JSON.parse(req.body)
      body["type"] == "text" &&
        body["text"]["body"] == "You picked green!"
    end
  end

  def test_choice_flow_list_reply_completes_flow
    # Set up session with choice mapping for list selection
    session_data = {
      "$start$" => "start",
      "whatsapp.choice_mapping" => {"Banana" => "banana"}
    }

    controller = create_whatsapp_controller(
      message: build_list_reply(item_id: "Banana")
    )

    run_processor(controller, ListChoiceFlow, session_data: session_data)

    # Should send completion message
    assert_requested :post, "#{@api_base_url}/123456789/messages" do |req|
      body = JSON.parse(req.body)
      body["type"] == "text" &&
        body["text"]["body"] == "You picked banana!"
    end
  end

  def test_media_flow_sends_image
    controller = create_whatsapp_controller(
      message: build_text_message(text: "show")
    )

    run_processor(controller, MediaFlow)

    # Should send image
    assert_requested :post, "#{@api_base_url}/123456789/messages" do |req|
      body = JSON.parse(req.body)
      body["type"] == "image" &&
        body["image"]["link"] == "https://example.com/photo.jpg" &&
        body["image"]["caption"] == "Here's an image"
    end
  end

  def test_document_flow_sends_document
    controller = create_whatsapp_controller(
      message: build_text_message(text: "show")
    )

    run_processor(controller, DocumentFlow)

    # Should send document
    assert_requested :post, "#{@api_base_url}/123456789/messages" do |req|
      body = JSON.parse(req.body)
      body["type"] == "document" &&
        body["document"]["link"] == "https://example.com/doc.pdf" &&
        body["document"]["filename"] == "report.pdf" &&
        body["document"]["caption"] == "Here's a document"
    end
  end

  # Blocker 1: media plus more than 3 choices used to raise ArgumentError
  # before this ever reached a renderer. 4 choices is above MAX_BUTTONS, so
  # the media goes out as its own image message, ahead of the interactive
  # list carrying all 4 rows - the shape build_selection_message_with_media
  # already builds, just previously unreachable from a flow.
  def test_media_with_more_than_three_choices_sends_media_then_list
    controller = create_whatsapp_controller(
      message: build_text_message(text: "start")
    )

    posts = []
    stub_request(:post, "#{@api_base_url}/123456789/messages").to_return do |req|
      posts << JSON.parse(req.body)
      {status: 200, body: {"messages" => [{"id" => "wamid.test123"}]}.to_json}
    end

    run_processor(controller, MediaChoiceFlow)

    media_post, list_post = posts

    assert_equal "image", media_post["type"]
    assert_equal "https://example.com/plans.png", media_post.dig("image", "link")

    assert_equal "interactive", list_post["type"]
    assert_equal "list", list_post.dig("interactive", "type")
    rows = list_post.dig("interactive", "action", "sections").flat_map { |s| s["rows"] }
    assert_equal 4, rows.length

    # Meta: "Body text. Maximum 1024 characters" for an interactive message body.
    assert_operator list_post.dig("interactive", "body", "text").to_s.bytesize, :<=, 1024
  end

  # Blocker 3: a typed "1" resolves against the menu's position map (the
  # labels are long enough that FlowChat::ChoiceTitles numbers them), then
  # the very next screen is free text. A stale map would rewrite a typed PIN
  # digit into the menu's first choice; clearing the maps unconditionally
  # before the app is called is what stops that.
  def test_typed_digit_on_free_text_screen_after_array_menu_stays_a_digit
    session_data = {}

    controller = create_whatsapp_controller(message: build_text_message(text: "start"))
    run_processor(controller, ArrayMenuThenPinFlow, session_data: session_data)
    assert_requested :post, "#{@api_base_url}/123456789/messages" do |req|
      body = JSON.parse(req.body)
      body["interactive"]["action"]["buttons"].length == 2
    end

    controller = create_whatsapp_controller(message: build_text_message(text: "1"))
    run_processor(controller, ArrayMenuThenPinFlow, session_data: session_data)
    assert_requested :post, "#{@api_base_url}/123456789/messages" do |req|
      JSON.parse(req.body).dig("text", "body") == "Enter your PIN:"
    end

    controller = create_whatsapp_controller(message: build_text_message(text: "1"))
    run_processor(controller, ArrayMenuThenPinFlow, session_data: session_data)
    # Bug present: "...and entered PIN A very long label...". Fixed: the
    # typed digit reaches the flow untouched.
    assert_requested :post, "#{@api_base_url}/123456789/messages" do |req|
      JSON.parse(req.body).dig("text", "body").to_s.end_with?("PIN 1.")
    end
  end

  # ============================================================================
  # WEBHOOK VERIFICATION TESTS
  # ============================================================================

  def test_webhook_verification_succeeds_with_valid_token
    controller = create_verification_controller(
      mode: "subscribe",
      verify_token: "test_verify_token",
      challenge: "challenge123"
    )

    run_processor(controller, GreetingFlow)

    assert_equal "challenge123", controller.rendered_plain
  end

  def test_webhook_verification_fails_with_invalid_token
    controller = create_verification_controller(
      mode: "subscribe",
      verify_token: "wrong_token",
      challenge: "challenge123"
    )

    run_processor(controller, GreetingFlow)

    assert_equal :forbidden, controller.last_head_status
  end

  # ============================================================================
  # WEBHOOK SIGNATURE VALIDATION TESTS
  # ============================================================================

  def test_webhook_rejects_invalid_signature
    config = FlowChat::Whatsapp::Configuration.new("signature_test")
    config.access_token = "test_access_token"
    config.phone_number_id = "123456789"
    config.verify_token = "test_verify_token"
    config.app_secret = "test_app_secret"
    config.skip_signature_validation = false  # Enable signature validation

    controller = create_whatsapp_controller(
      message: build_text_message(text: "hello"),
      signature: "sha256=invalid_signature"
    )

    run_processor(controller, GreetingFlow, config: config)

    assert_equal :ok, controller.last_head_status
    # Should NOT send any message
    assert_not_requested :post, "#{@api_base_url}/123456789/messages"
  end

  def test_webhook_accepts_valid_signature
    config = FlowChat::Whatsapp::Configuration.new("signature_test2")
    config.access_token = "test_access_token"
    config.phone_number_id = "123456789"
    config.verify_token = "test_verify_token"
    config.app_secret = "test_app_secret"
    config.skip_signature_validation = false

    body = build_webhook_body(build_text_message(text: "hello"))
    signature = compute_signature(body.to_json, "test_app_secret")

    controller = create_whatsapp_controller_with_body(
      body: body,
      signature: signature
    )

    run_processor(controller, GreetingFlow, config: config)

    # Should send message (signature valid)
    assert_requested :post, "#{@api_base_url}/123456789/messages"
  end

  def test_webhook_accepts_when_signature_validation_disabled
    controller = create_whatsapp_controller(
      message: build_text_message(text: "hello")
      # No signature provided, validation disabled via skip_signature_validation
    )

    run_processor(controller, GreetingFlow)

    # Should process successfully
    assert_requested :post, "#{@api_base_url}/123456789/messages"
  end

  # ============================================================================
  # CONTEXT EXTRACTION TESTS
  # ============================================================================

  def test_context_extracts_user_info_from_message
    controller = create_whatsapp_controller(
      message: build_text_message(text: "test"),
      contact_name: "John Doe"
    )

    captured_context = nil
    run_processor(controller, GreetingFlow) do |context|
      captured_context = context.dup
    end

    assert_equal "+256700123456", captured_context["request.id"]
    assert_equal "+256700123456", captured_context["request.user_id"]
    assert_equal "John Doe", captured_context["request.user_name"]
    assert_equal "+256700123456", captured_context["request.msisdn"]
    assert_equal :whatsapp, captured_context["request.platform"]
    assert_equal :whatsapp_cloud_api, captured_context["request.gateway"]
  end

  def test_context_extracts_location_message
    controller = create_whatsapp_controller(
      message: build_location_message(latitude: 51.5074, longitude: -0.1278, name: "London", address: "UK")
    )

    captured_context = nil
    run_processor(controller, GreetingFlow) do |context|
      captured_context = context.dup
    end

    assert_equal "", captured_context.input
    assert_equal 51.5074, captured_context["request.location"][:latitude]
    assert_equal(-0.1278, captured_context["request.location"][:longitude])
    assert_equal "London", captured_context["request.location"][:name]
    assert_equal "UK", captured_context["request.location"][:address]
  end

  def test_context_extracts_image_message
    controller = create_whatsapp_controller(
      message: build_image_message(
        media_id: "media123",
        mime_type: "image/jpeg",
        caption: "Test image"
      )
    )

    captured_context = nil
    run_processor(controller, GreetingFlow) do |context|
      captured_context = context.dup
    end

    # The caption becomes the turn's text (input); no sentinel when text is present.
    assert_equal "Test image", captured_context.input
    assert_equal :image, captured_context["request.media"][:type]
    assert_equal "media123", captured_context["request.media"][:id]
    assert_equal "image/jpeg", captured_context["request.media"][:mime_type]
    assert_equal "Test image", captured_context["request.media"][:caption]
  end

  def test_context_extracts_document_message
    controller = create_whatsapp_controller(
      message: build_document_message(
        media_id: "doc123",
        mime_type: "application/pdf",
        caption: "Test document"
      )
    )

    captured_context = nil
    run_processor(controller, GreetingFlow) do |context|
      captured_context = context.dup
    end

    assert_equal "Test document", captured_context.input
    assert_equal :document, captured_context["request.media"][:type]
    assert_equal "doc123", captured_context["request.media"][:id]
    assert_equal "application/pdf", captured_context["request.media"][:mime_type]
  end

  def test_context_extracts_audio_message
    controller = create_whatsapp_controller(
      message: build_audio_message(
        media_id: "audio123",
        mime_type: "audio/ogg"
      )
    )

    captured_context = nil
    run_processor(controller, GreetingFlow) do |context|
      captured_context = context.dup
    end

    assert_equal "", captured_context.input
    assert_equal :audio, captured_context["request.media"][:type]
    assert_equal "audio123", captured_context["request.media"][:id]
  end

  def test_context_extracts_video_message
    controller = create_whatsapp_controller(
      message: build_video_message(
        media_id: "video123",
        mime_type: "video/mp4",
        caption: "Test video"
      )
    )

    captured_context = nil
    run_processor(controller, GreetingFlow) do |context|
      captured_context = context.dup
    end

    assert_equal "Test video", captured_context.input
    assert_equal :video, captured_context["request.media"][:type]
    assert_equal "video123", captured_context["request.media"][:id]
    assert_equal "video/mp4", captured_context["request.media"][:mime_type]
  end

  def test_context_extracts_contact_message
    controller = create_whatsapp_controller(
      message: build_contact_message(
        name: "Jane Smith",
        phone: "+1234567890"
      )
    )

    captured_context = nil
    run_processor(controller, GreetingFlow) do |context|
      captured_context = context.dup
    end

    assert_equal "", captured_context.input
    assert_equal "Jane Smith", captured_context["request.contact"][:name]
    assert_equal "+1234567890", captured_context["request.contact"][:phone_number]
  end

  def test_context_extracts_sticker_message
    controller = create_whatsapp_controller(
      message: build_sticker_message(
        media_id: "sticker123",
        mime_type: "image/webp",
        animated: true
      )
    )

    captured_context = nil
    run_processor(controller, GreetingFlow) do |context|
      captured_context = context.dup
    end

    assert_equal "", captured_context.input
    assert_equal :sticker, captured_context["request.media"][:type]
    assert_equal "sticker123", captured_context["request.media"][:id]
    assert_equal true, captured_context["request.media"][:animated]
  end

  # ============================================================================
  # CHOICE MAPPER INTEGRATION TESTS
  # ============================================================================

  def test_choice_mapper_stores_choices_in_session
    session_data = {}

    controller = create_whatsapp_controller(
      message: build_text_message(text: "start")
    )

    run_processor(controller, ChoiceFlow, session_data: session_data)

    # Choice mapper should store choices with key "whatsapp.choice_mapping"
    assert session_data.key?("whatsapp.choice_mapping")
    # The mapping is from generated IDs to original keys
    mapping = session_data["whatsapp.choice_mapping"]
    assert mapping.value?("red")
    assert mapping.value?("green")
    assert mapping.value?("blue")
  end

  def test_choice_mapper_maps_button_reply_to_original_key
    # Include $start$ to indicate conversation has started
    session_data = {
      "$start$" => "start",
      "whatsapp.choice_mapping" => {"Red" => "red", "Green" => "green", "Blue" => "blue"}
    }

    controller = create_whatsapp_controller(
      message: build_button_reply(button_id: "Green")
    )

    run_processor(controller, ChoiceFlow, session_data: session_data)

    # Should complete flow with selected choice
    assert_requested :post, "#{@api_base_url}/123456789/messages" do |req|
      body = JSON.parse(req.body)
      body["text"]["body"] == "You picked green!"
    end
  end

  # ============================================================================
  # PHONE NUMBER ID VALIDATION TESTS
  # ============================================================================

  def test_webhook_rejects_mismatched_phone_number_id
    controller = create_whatsapp_controller(
      message: build_text_message(text: "hello"),
      phone_number_id: "different_phone_number_id"
    )

    run_processor(controller, GreetingFlow)

    assert_equal :forbidden, controller.last_head_status
    # Should NOT send any message
    assert_not_requested :post, "#{@api_base_url}/123456789/messages"
  end

  # ============================================================================
  # EDGE CASES
  # ============================================================================

  def test_handles_empty_webhook_entry
    controller = create_whatsapp_controller_with_body(
      body: {"object" => "whatsapp_business_account", "entry" => []}
    )

    run_processor(controller, GreetingFlow)

    assert_equal :ok, controller.last_head_status
    # Should NOT send any message
    assert_not_requested :post, "#{@api_base_url}/123456789/messages"
  end

  def test_handles_status_update_webhook
    controller = create_whatsapp_controller_with_body(
      body: {
        "object" => "whatsapp_business_account",
        "entry" => [{
          "id" => "123",
          "changes" => [{
            "value" => {
              "messaging_product" => "whatsapp",
              "metadata" => {
                "display_phone_number" => "256700000000",
                "phone_number_id" => "123456789"
              },
              "statuses" => [{
                "id" => "wamid.test123",
                "status" => "delivered",
                "timestamp" => "1234567890"
              }]
            },
            "field" => "messages"
          }]
        }]
      }
    )

    run_processor(controller, GreetingFlow)

    assert_equal :ok, controller.last_head_status
    # Should NOT send any message for status updates
    assert_not_requested :post, "#{@api_base_url}/123456789/messages"
  end

  private

  def build_text_message(text: nil, from: "256700123456", message_id: nil)
    message_id ||= "wamid.#{rand(1000)}"
    {
      "from" => from,
      "id" => message_id,
      "timestamp" => Time.now.to_i.to_s,
      "type" => "text",
      "text" => {"body" => text}
    }
  end

  def build_button_reply(button_id:, from: "256700123456")
    {
      "from" => from,
      "id" => "wamid.#{rand(1000)}",
      "timestamp" => Time.now.to_i.to_s,
      "type" => "interactive",
      "interactive" => {
        "type" => "button_reply",
        "button_reply" => {
          "id" => button_id,
          "title" => button_id
        }
      }
    }
  end

  def build_list_reply(item_id:, from: "256700123456")
    {
      "from" => from,
      "id" => "wamid.#{rand(1000)}",
      "timestamp" => Time.now.to_i.to_s,
      "type" => "interactive",
      "interactive" => {
        "type" => "list_reply",
        "list_reply" => {
          "id" => item_id,
          "title" => item_id
        }
      }
    }
  end

  def build_location_message(latitude:, longitude:, name: nil, address: nil, from: "256700123456")
    location = {
      "latitude" => latitude,
      "longitude" => longitude
    }
    location["name"] = name if name
    location["address"] = address if address

    {
      "from" => from,
      "id" => "wamid.#{rand(1000)}",
      "timestamp" => Time.now.to_i.to_s,
      "type" => "location",
      "location" => location
    }
  end

  def build_image_message(media_id:, mime_type: "image/jpeg", caption: nil, from: "256700123456")
    image = {
      "id" => media_id,
      "mime_type" => mime_type
    }
    image["caption"] = caption if caption

    {
      "from" => from,
      "id" => "wamid.#{rand(1000)}",
      "timestamp" => Time.now.to_i.to_s,
      "type" => "image",
      "image" => image
    }
  end

  def build_document_message(media_id:, mime_type: "application/pdf", caption: nil, from: "256700123456")
    document = {
      "id" => media_id,
      "mime_type" => mime_type
    }
    document["caption"] = caption if caption

    {
      "from" => from,
      "id" => "wamid.#{rand(1000)}",
      "timestamp" => Time.now.to_i.to_s,
      "type" => "document",
      "document" => document
    }
  end

  def build_audio_message(media_id:, mime_type: "audio/ogg", from: "256700123456")
    {
      "from" => from,
      "id" => "wamid.#{rand(1000)}",
      "timestamp" => Time.now.to_i.to_s,
      "type" => "audio",
      "audio" => {
        "id" => media_id,
        "mime_type" => mime_type
      }
    }
  end

  def build_video_message(media_id:, mime_type: "video/mp4", caption: nil, from: "256700123456")
    video = {
      "id" => media_id,
      "mime_type" => mime_type
    }
    video["caption"] = caption if caption

    {
      "from" => from,
      "id" => "wamid.#{rand(1000)}",
      "timestamp" => Time.now.to_i.to_s,
      "type" => "video",
      "video" => video
    }
  end

  def build_contact_message(name:, phone:, from: "256700123456")
    {
      "from" => from,
      "id" => "wamid.#{rand(1000)}",
      "timestamp" => Time.now.to_i.to_s,
      "type" => "contacts",
      "contacts" => [{
        "name" => {
          "formatted_name" => name,
          "first_name" => name.split.first,
          "last_name" => name.split.last
        },
        "phones" => [{
          "phone" => phone,
          "type" => "CELL"
        }]
      }]
    }
  end

  def build_sticker_message(media_id:, mime_type: "image/webp", animated: false, from: "256700123456")
    {
      "from" => from,
      "id" => "wamid.#{rand(1000)}",
      "timestamp" => Time.now.to_i.to_s,
      "type" => "sticker",
      "sticker" => {
        "id" => media_id,
        "mime_type" => mime_type,
        "animated" => animated
      }
    }
  end

  def build_webhook_body(message, contact_name: "John Doe", phone_number_id: "123456789")
    {
      "object" => "whatsapp_business_account",
      "entry" => [{
        "id" => "123",
        "changes" => [{
          "value" => {
            "messaging_product" => "whatsapp",
            "metadata" => {
              "display_phone_number" => "256700000000",
              "phone_number_id" => phone_number_id
            },
            "contacts" => [{
              "profile" => {"name" => contact_name},
              "wa_id" => message["from"]
            }],
            "messages" => [message]
          },
          "field" => "messages"
        }]
      }]
    }
  end

  def create_whatsapp_controller(message: nil, contact_name: "John Doe", signature: nil, phone_number_id: "123456789")
    body = build_webhook_body(message, contact_name: contact_name, phone_number_id: phone_number_id)
    create_whatsapp_controller_with_body(body: body, signature: signature)
  end

  def create_whatsapp_controller_with_body(body:, signature: nil)
    controller = Object.new
    request = Object.new
    body_json = body.to_json
    body_io = StringIO.new(body_json)

    request.define_singleton_method(:get?) { false }
    request.define_singleton_method(:post?) { true }
    request.define_singleton_method(:body) { body_io }
    request.define_singleton_method(:params) { {} }
    request.define_singleton_method(:request_method) { "POST" }
    request.define_singleton_method(:path) { "/webhook" }
    request.define_singleton_method(:headers) do
      h = {}
      h["X-Hub-Signature-256"] = signature if signature
      h
    end
    request.define_singleton_method(:cookies) { {} }

    controller.define_singleton_method(:request) { request }
    controller.define_singleton_method(:head) { |status| @last_head_status = status }
    controller.define_singleton_method(:last_head_status) { @last_head_status }
    controller.define_singleton_method(:render) { |**options| @rendered = options }
    controller.define_singleton_method(:rendered) { @rendered }
    controller.define_singleton_method(:rendered_plain) { @rendered&.dig(:plain) }

    controller
  end

  def create_verification_controller(mode:, verify_token:, challenge:)
    controller = Object.new
    request = Object.new

    params = {
      "hub.mode" => mode,
      "hub.verify_token" => verify_token,
      "hub.challenge" => challenge
    }

    request.define_singleton_method(:get?) { true }
    request.define_singleton_method(:post?) { false }
    request.define_singleton_method(:params) { params }
    request.define_singleton_method(:request_method) { "GET" }
    request.define_singleton_method(:path) { "/webhook" }

    controller.define_singleton_method(:request) { request }
    controller.define_singleton_method(:head) { |status| @last_head_status = status }
    controller.define_singleton_method(:last_head_status) { @last_head_status }
    controller.define_singleton_method(:render) { |**options| @rendered = options }
    controller.define_singleton_method(:rendered) { @rendered }
    controller.define_singleton_method(:rendered_plain) { @rendered&.dig(:plain) }

    controller
  end

  def compute_signature(body, secret)
    signature = OpenSSL::HMAC.hexdigest(
      OpenSSL::Digest.new("sha256"),
      secret,
      body
    )
    "sha256=#{signature}"
  end

  def create_session_store(data)
    Class.new do
      define_method(:initialize) { |_context| @data = data }
      define_method(:get) { |key| @data[key.to_s] }
      define_method(:set) { |key, value| @data[key.to_s] = value }
      define_method(:delete) { |key| @data.delete(key.to_s) }
      define_method(:clear) { @data.clear }
      define_method(:destroy) { @data.clear }
    end
  end

  def run_processor(controller, flow_class, session_data: {}, config: nil, &context_callback)
    config ||= @config
    session_store = create_session_store(session_data)

    processor = FlowChat::Processor.new(controller) do |c|
      c.use_gateway FlowChat::Whatsapp::Gateway::CloudApi, config
      c.use_session_store session_store

      if context_callback
        c.use_middleware Class.new {
          define_method(:initialize) { |app|
            @app = app
            @callback = context_callback
          }
          define_method(:call) { |context|
            @callback.call(context)
            @app.call(context)
          }
        }
      end
    end

    processor.run(flow_class, :main_page)
  end
end

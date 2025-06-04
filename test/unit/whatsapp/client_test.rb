require "test_helper"
require "webmock/minitest"

class WhatsappClientTest < Minitest::Test
  def setup
    @config = FlowChat::Whatsapp::Configuration.new("test_config")
    @config.access_token = "test_token"
    @config.phone_number_id = "123456789"
    @client = FlowChat::Whatsapp::Client.new(@config)

    # Setup WebMock for HTTP request stubbing
    WebMock.enable!
    WebMock.reset!
  end

  def teardown
    WebMock.disable!
    WebMock.reset!
  end

  # ============================================================================
  # HELPER METHOD TESTS
  # ============================================================================

  def test_url_detection
    assert @client.send(:url?, "https://example.com/file.jpg")
    assert @client.send(:url?, "http://example.com/file.jpg")
    refute @client.send(:url?, "/path/to/file.jpg")
    refute @client.send(:url?, "file.jpg")
    refute @client.send(:url?, "media_id_123")
  end

  def test_extract_filename_from_url
    assert_equal "image.jpg", @client.send(:extract_filename_from_url, "https://example.com/path/image.jpg")
    assert_equal "document.pdf", @client.send(:extract_filename_from_url, "https://example.com/document.pdf")
    assert_equal "path", @client.send(:extract_filename_from_url, "https://example.com/path/")
    assert_equal "invalid-url", @client.send(:extract_filename_from_url, "invalid-url")
  end

  def test_cleanup_temp_file
    temp_file = Tempfile.new(["test", ".jpg"])
    temp_file.write("test data")
    temp_file.close

    file_path = temp_file.path
    assert File.exist?(file_path)

    File.unlink(file_path) if File.exist?(file_path)
    refute File.exist?(file_path)
  end

  # ============================================================================
  # BASIC MESSAGE SENDING TESTS
  # ============================================================================

  def test_send_text_message
    stub_whatsapp_messages_api(success_response)

    result = @client.send_text("+1234567890", "Hello, World!")

    assert_equal "message_123", result["messages"][0]["id"]
    assert_requested :post, whatsapp_messages_url,
      body: hash_including({
        "messaging_product" => "whatsapp",
        "to" => "+1234567890",
        "type" => "text",
        "text" => {"body" => "Hello, World!"}
      })
  end

  def test_send_buttons_message
    stub_whatsapp_messages_api(success_response)

    buttons = [
      {id: "btn1", title: "Button 1"},
      {id: "btn2", title: "Button 2"}
    ]

    result = @client.send_buttons("+1234567890", "Choose an option:", buttons)

    assert_equal "message_123", result["messages"][0]["id"]
    assert_requested :post, whatsapp_messages_url,
      body: hash_including({
        "messaging_product" => "whatsapp",
        "to" => "+1234567890",
        "type" => "interactive",
        "interactive" => hash_including({
          "type" => "button",
          "body" => {"text" => "Choose an option:"}
        })
      })
  end

  def test_send_list_message
    stub_whatsapp_messages_api(success_response)

    sections = [
      {
        title: "Section 1",
        rows: [
          {id: "row1", title: "Row 1", description: "Description 1"}
        ]
      }
    ]

    result = @client.send_list("+1234567890", "Select from menu:", sections)

    assert_equal "message_123", result["messages"][0]["id"]
    assert_requested :post, whatsapp_messages_url,
      body: hash_including({
        "messaging_product" => "whatsapp",
        "to" => "+1234567890",
        "type" => "interactive",
        "interactive" => hash_including({
          "type" => "list",
          "body" => {"text" => "Select from menu:"}
        })
      })
  end

  def test_send_template_message
    stub_whatsapp_messages_api(success_response)

    components = [
      {
        type: "body",
        parameters: [
          {type: "text", text: "John"}
        ]
      }
    ]

    result = @client.send_template("+1234567890", "hello_world", components, "en_US")

    assert_equal "message_123", result["messages"][0]["id"]
    assert_requested :post, whatsapp_messages_url,
      body: hash_including({
        "messaging_product" => "whatsapp",
        "to" => "+1234567890",
        "type" => "template",
        "template" => hash_including({
          "name" => "hello_world",
          "language" => {"code" => "en_US"},
          "components" => components
        })
      })
  end

  # ============================================================================
  # MEDIA MESSAGE TESTS
  # ============================================================================

  def test_send_image_with_url
    stub_whatsapp_messages_api(success_response)

    result = @client.send_image("+1234567890", "https://example.com/image.jpg", "Photo caption")

    assert_equal "message_123", result["messages"][0]["id"]
    assert_requested :post, whatsapp_messages_url,
      body: hash_including({
        "messaging_product" => "whatsapp",
        "to" => "+1234567890",
        "type" => "image",
        "image" => {
          "link" => "https://example.com/image.jpg",
          "caption" => "Photo caption"
        }
      })
  end

  def test_send_image_with_media_id
    stub_whatsapp_messages_api(success_response)

    result = @client.send_image("+1234567890", "media_id_123", "Photo caption")

    assert_equal "message_123", result["messages"][0]["id"]
    assert_requested :post, whatsapp_messages_url,
      body: hash_including({
        "messaging_product" => "whatsapp",
        "to" => "+1234567890",
        "type" => "image",
        "image" => {
          "id" => "media_id_123",
          "caption" => "Photo caption"
        }
      })
  end

  def test_send_document_with_url_and_filename
    stub_whatsapp_messages_api(success_response)

    result = @client.send_document("+1234567890", "https://example.com/doc.pdf", "Document caption", "receipt.pdf")

    assert_equal "message_123", result["messages"][0]["id"]
    assert_requested :post, whatsapp_messages_url,
      body: hash_including({
        "messaging_product" => "whatsapp",
        "to" => "+1234567890",
        "type" => "document",
        "document" => {
          "link" => "https://example.com/doc.pdf",
          "caption" => "Document caption",
          "filename" => "receipt.pdf"
        }
      })
  end

  def test_send_document_extracts_filename_from_url
    stub_whatsapp_messages_api(success_response)

    @client.send_document("+1234567890", "https://example.com/receipt.pdf", "Document caption")

    assert_requested :post, whatsapp_messages_url,
      body: hash_including({
        "document" => hash_including({
          "filename" => "receipt.pdf"
        })
      })
  end

  def test_send_video_with_url
    stub_whatsapp_messages_api(success_response)

    result = @client.send_video("+1234567890", "https://example.com/video.mp4", "Video caption")

    assert_equal "message_123", result["messages"][0]["id"]
    assert_requested :post, whatsapp_messages_url,
      body: hash_including({
        "messaging_product" => "whatsapp",
        "to" => "+1234567890",
        "type" => "video",
        "video" => {
          "link" => "https://example.com/video.mp4",
          "caption" => "Video caption"
        }
      })
  end

  def test_send_audio_with_media_id
    stub_whatsapp_messages_api(success_response)

    result = @client.send_audio("+1234567890", "audio_media_id_123")

    assert_equal "message_123", result["messages"][0]["id"]
    assert_requested :post, whatsapp_messages_url,
      body: hash_including({
        "messaging_product" => "whatsapp",
        "to" => "+1234567890",
        "type" => "audio",
        "audio" => {
          "id" => "audio_media_id_123"
        }
      })
  end

  def test_send_sticker_with_url
    stub_whatsapp_messages_api(success_response)

    result = @client.send_sticker("+1234567890", "https://example.com/sticker.webp")

    assert_equal "message_123", result["messages"][0]["id"]
    assert_requested :post, whatsapp_messages_url,
      body: hash_including({
        "messaging_product" => "whatsapp",
        "to" => "+1234567890",
        "type" => "sticker",
        "sticker" => {
          "link" => "https://example.com/sticker.webp"
        }
      })
  end

  # ============================================================================
  # MEDIA UPLOAD TESTS
  # ============================================================================

  def test_upload_media_with_file_path
    stub_media_upload_api({"id" => "uploaded_media_123"})

    # Create a test file
    test_file = Tempfile.new(["test", ".jpg"])
    test_file.write("fake image data")
    test_file.close

    result = @client.upload_media(test_file.path, "image/jpeg")

    assert_equal "uploaded_media_123", result
    assert_requested :post, whatsapp_media_url

    test_file.unlink
  end

  def test_upload_media_with_io_object
    stub_media_upload_api({"id" => "uploaded_media_456"})

    io_object = StringIO.new("fake file content")

    result = @client.upload_media(io_object, "application/pdf", "document.pdf")

    assert_equal "uploaded_media_456", result
    assert_requested :post, whatsapp_media_url
  end

  def test_upload_media_requires_mime_type
    error = assert_raises(ArgumentError) do
      @client.upload_media("test.jpg", nil)
    end

    assert_equal "mime_type is required", error.message
  end

  def test_upload_media_file_not_found
    error = assert_raises(ArgumentError) do
      @client.upload_media("nonexistent_file.jpg", "image/jpeg")
    end

    assert_match(/File not found/, error.message)
  end

  def test_upload_media_api_error
    stub_media_upload_api_error("Invalid file format")

    test_file = Tempfile.new(["test", ".jpg"])
    test_file.write("fake image data")
    test_file.close

    error = assert_raises(StandardError) do
      @client.upload_media(test_file.path, "image/jpeg")
    end

    assert_match(/Media upload failed/, error.message)

    test_file.unlink
  end

  # ============================================================================
  # MEDIA URL AND DOWNLOAD TESTS
  # ============================================================================

  def test_get_media_url
    media_response = {
      "url" => "https://media.example.com/file.jpg",
      "mime_type" => "image/jpeg",
      "sha256" => "abc123",
      "file_size" => "12345",
      "id" => "media_123"
    }

    stub_request(:get, "https://graph.facebook.com/v18.0/media_123")
      .with(headers: {"Authorization" => "Bearer test_token"})
      .to_return(status: 200, body: media_response.to_json)

    result = @client.get_media_url("media_123")

    assert_equal "https://media.example.com/file.jpg", result
  end

  def test_get_media_url_error
    stub_request(:get, "https://graph.facebook.com/v18.0/media_123")
      .with(headers: {"Authorization" => "Bearer test_token"})
      .to_return(status: 404, body: {"error" => "Media not found"}.to_json)

    result = @client.get_media_url("media_123")

    assert_nil result
  end

  def test_download_media
    # First stub the media URL request
    media_response = {
      "url" => "https://media.example.com/file.jpg"
    }

    stub_request(:get, "https://graph.facebook.com/v18.0/media_123")
      .with(headers: {"Authorization" => "Bearer test_token"})
      .to_return(status: 200, body: media_response.to_json)

    # Then stub the actual media download
    stub_request(:get, "https://media.example.com/file.jpg")
      .with(headers: {"Authorization" => "Bearer test_token"})
      .to_return(status: 200, body: "binary image data")

    result = @client.download_media("media_123")

    assert_equal "binary image data", result
  end

  def test_download_media_url_fetch_fails
    stub_request(:get, "https://graph.facebook.com/v18.0/media_123")
      .with(headers: {"Authorization" => "Bearer test_token"})
      .to_return(status: 404, body: {"error" => "Media not found"}.to_json)

    result = @client.download_media("media_123")

    assert_nil result
  end

  # ============================================================================
  # MESSAGE BUILDING TESTS
  # ============================================================================

  def test_build_message_payload_text
    response = [:text, "Hello, World!", {}]

    payload = @client.build_message_payload(response, "+1234567890")

    expected = {
      messaging_product: "whatsapp",
      to: "+1234567890",
      type: "text",
      text: {body: "Hello, World!"}
    }

    assert_equal expected, payload
  end

  def test_build_message_payload_interactive_buttons
    response = [:interactive_buttons, "Choose option:", {buttons: [{id: "1", title: "Option 1"}]}]

    payload = @client.build_message_payload(response, "+1234567890")

    assert_equal "whatsapp", payload[:messaging_product]
    assert_equal "+1234567890", payload[:to]
    assert_equal "interactive", payload[:type]
    assert_equal "button", payload[:interactive][:type]
    assert_equal "Choose option:", payload[:interactive][:body][:text]
  end

  def test_build_message_payload_media_image
    response = [:media_image, "", {url: "https://example.com/image.jpg", caption: "Photo"}]

    payload = @client.build_message_payload(response, "+1234567890")

    expected = {
      messaging_product: "whatsapp",
      to: "+1234567890",
      type: "image",
      image: {link: "https://example.com/image.jpg", caption: "Photo"}
    }

    assert_equal expected, payload
  end

  def test_build_message_payload_unknown_type
    response = [:unknown_type, "Content", {}]

    payload = @client.build_message_payload(response, "+1234567890")

    # Should default to text message
    expected = {
      messaging_product: "whatsapp",
      to: "+1234567890",
      type: "text",
      text: {body: "Content"}
    }

    assert_equal expected, payload
  end

  # ============================================================================
  # ERROR HANDLING TESTS
  # ============================================================================

  def test_api_error_handling
    stub_request(:post, whatsapp_messages_url)
      .to_return(status: 400, body: {"error" => "Invalid request"}.to_json)

    result = @client.send_text("+1234567890", "Hello")

    assert_nil result
  end

  def test_network_error_handling
    # Test that network errors are raised (not handled by client)
    stub_request(:post, whatsapp_messages_url)
      .to_raise(Net::OpenTimeout)

    # The client should allow the exception to bubble up
    assert_raises(Net::OpenTimeout) do
      @client.send_text("+1234567890", "Hello")
    end
  end

  # ============================================================================
  # MIME TYPE DETECTION TESTS
  # ============================================================================

  def test_get_media_mime_type
    stub_request(:head, "https://example.com/image.jpg")
      .to_return(status: 200, headers: {"Content-Type" => "image/jpeg"})

    mime_type = @client.get_media_mime_type("https://example.com/image.jpg")

    assert_equal "image/jpeg", mime_type
  end

  def test_get_media_mime_type_error
    stub_request(:head, "https://example.com/image.jpg").to_timeout

    mime_type = @client.get_media_mime_type("https://example.com/image.jpg")

    assert_nil mime_type
  end

  # ============================================================================
  # METHOD EXISTENCE TESTS
  # ============================================================================

  def test_media_methods_exist
    assert_respond_to @client, :send_image
    assert_respond_to @client, :send_document
    assert_respond_to @client, :send_video
    assert_respond_to @client, :send_audio
    assert_respond_to @client, :send_sticker
    assert_respond_to @client, :upload_media
    assert_respond_to @client, :get_media_url
    assert_respond_to @client, :download_media
  end

  def test_media_methods_accept_correct_parameters
    # These methods will raise errors when called with invalid parameters
    # Test that they expect the right number of parameters

    # send_image expects (to, image_url_or_id, caption=nil, mime_type=nil)
    assert_raises(ArgumentError) { @client.send_image }
    assert_raises(ArgumentError) { @client.send_image("+1234567890") }

    # send_document expects (to, document_url_or_id, caption=nil, filename=nil, mime_type=nil)
    assert_raises(ArgumentError) { @client.send_document }
    assert_raises(ArgumentError) { @client.send_document("+1234567890") }

    # send_video expects (to, video_url_or_id, caption=nil, mime_type=nil)
    assert_raises(ArgumentError) { @client.send_video }
    assert_raises(ArgumentError) { @client.send_video("+1234567890") }

    # send_audio expects (to, audio_url_or_id, mime_type=nil)
    assert_raises(ArgumentError) { @client.send_audio }
    assert_raises(ArgumentError) { @client.send_audio("+1234567890") }

    # send_sticker expects (to, sticker_url_or_id, mime_type=nil)
    assert_raises(ArgumentError) { @client.send_sticker }
    assert_raises(ArgumentError) { @client.send_sticker("+1234567890") }

    # upload_media expects (file_path_or_io, mime_type, filename=nil)
    assert_raises(ArgumentError) { @client.upload_media }
  end

  private

  # ============================================================================
  # HELPER METHODS
  # ============================================================================

  def whatsapp_messages_url
    "https://graph.facebook.com/v18.0/#{@config.phone_number_id}/messages"
  end

  def whatsapp_media_url
    "https://graph.facebook.com/v18.0/#{@config.phone_number_id}/media"
  end

  def success_response
    {
      "messaging_product" => "whatsapp",
      "contacts" => [{"input" => "+1234567890", "wa_id" => "+1234567890"}],
      "messages" => [{"id" => "message_123"}]
    }
  end

  def stub_whatsapp_messages_api(response)
    stub_request(:post, whatsapp_messages_url)
      .with(headers: {"Authorization" => "Bearer test_token", "Content-Type" => "application/json"})
      .to_return(status: 200, body: response.to_json)
  end

  def stub_media_upload_api(response)
    stub_request(:post, whatsapp_media_url)
      .with(headers: {"Authorization" => "Bearer test_token"})
      .to_return(status: 200, body: response.to_json)
  end

  def stub_media_upload_api_error(error_message)
    stub_request(:post, whatsapp_media_url)
      .with(headers: {"Authorization" => "Bearer test_token"})
      .to_return(status: 400, body: {"error" => error_message}.to_json)
  end
end

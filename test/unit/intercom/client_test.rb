require "test_helper"
require "webmock/minitest"

class FlowChat::Intercom::ClientTest < Minitest::Test
  def setup
    # Mock configuration
    @config = FlowChat::Intercom::Configuration.new("test")
    @config.access_token = "test_access_token"
    @config.client_secret = "test_client_secret"
    @config.admin_id = "test_admin_id"

    @client = FlowChat::Intercom::Client.new(@config)

    # Enable WebMock
    WebMock.enable!
  end

  def teardown
    # Disable and reset WebMock
    WebMock.disable!
    WebMock.reset!
  end

  def test_initialize_with_config
    assert_equal @config, @client.instance_variable_get(:@config)
  end

  def test_send_message_text_response
    conversation_id = "conv_123"
    response = [:text, "Hello, how can I help?", {}]

    expected_payload = {
      message_type: "comment",
      type: "admin",
      admin_id: "test_admin_id",
      body: "Hello, how can I help?"
    }

    mock_api_response = {"id" => "msg_456", "type" => "comment"}

    stub_request(:post, "https://api.intercom.io/conversations/#{conversation_id}/reply")
      .with(
        body: expected_payload.to_json,
        headers: @config.api_headers
      )
      .to_return(status: 200, body: mock_api_response.to_json)

    result = @client.send_message(conversation_id, response)

    assert_equal mock_api_response, result
    assert_equal "msg_456", result["id"]
  end

  def test_send_message_note_response
    conversation_id = "conv_123"
    response = [:note, "Internal note for admins", {}]

    expected_payload = {
      message_type: "note",
      type: "admin",
      admin_id: "test_admin_id",
      body: "Internal note for admins"
    }

    mock_api_response = {"id" => "note_789", "type" => "note"}

    stub_request(:post, "https://api.intercom.io/conversations/#{conversation_id}/reply")
      .with(
        body: expected_payload.to_json,
        headers: @config.api_headers
      )
      .to_return(status: 200, body: mock_api_response.to_json)

    result = @client.send_message(conversation_id, response)

    assert_equal mock_api_response, result
  end

  def test_send_message_unknown_type_defaults_to_comment
    conversation_id = "conv_123"
    response = [:unknown_type, "Some content", {}]

    expected_payload = {
      message_type: "comment",
      type: "admin",
      admin_id: "test_admin_id",
      body: "Some content"
    }

    mock_api_response = {"id" => "msg_default", "type" => "comment"}

    stub_request(:post, "https://api.intercom.io/conversations/#{conversation_id}/reply")
      .with(
        body: expected_payload.to_json,
        headers: @config.api_headers
      )
      .to_return(status: 200, body: mock_api_response.to_json)

    result = @client.send_message(conversation_id, response)

    assert_equal mock_api_response, result
  end

  def test_send_message_api_failure
    conversation_id = "conv_123"
    response = [:text, "Hello", {}]

    stub_request(:post, "https://api.intercom.io/conversations/#{conversation_id}/reply")
      .to_return(status: 400, body: {"error" => "Bad request"}.to_json)

    result = @client.send_message(conversation_id, response)

    assert_nil result
  end

  def test_send_message_network_timeout
    conversation_id = "conv_123"
    response = [:text, "Hello", {}]

    stub_request(:post, "https://api.intercom.io/conversations/#{conversation_id}/reply")
      .to_timeout

    assert_raises(Net::OpenTimeout) do
      @client.send_message(conversation_id, response)
    end
  end

  def test_reply_to_conversation
    conversation_id = "conv_123"
    text = "This is a text reply"

    expected_payload = {
      message_type: "comment",
      type: "admin",
      admin_id: "test_admin_id",
      body: text
    }

    mock_api_response = {"id" => "msg_reply", "type" => "comment"}

    stub_request(:post, "https://api.intercom.io/conversations/#{conversation_id}/reply")
      .with(
        body: expected_payload.to_json,
        headers: @config.api_headers
      )
      .to_return(status: 200, body: mock_api_response.to_json)

    result = @client.reply_to_conversation(conversation_id, text)

    assert_equal mock_api_response, result
  end

  def test_assign_conversation_to_admin
    conversation_id = "conv_123"
    admin_id = "admin_456"

    expected_payload = {
      message_type: "assignment",
      type: "admin",
      admin_id: admin_id
    }

    mock_api_response = {"id" => "assignment_789", "type" => "assignment"}

    stub_request(:post, "https://api.intercom.io/conversations/#{conversation_id}/reply")
      .with(
        body: expected_payload.to_json,
        headers: @config.api_headers
      )
      .to_return(status: 200, body: mock_api_response.to_json)

    result = @client.assign_conversation(conversation_id, admin_id)

    assert_equal mock_api_response, result
  end

  def test_assign_conversation_to_team
    conversation_id = "conv_123"
    admin_id = "admin_456"
    team_id = "team_789"

    expected_payload = {
      message_type: "assignment",
      type: "admin",
      admin_id: admin_id,
      team_id: team_id
    }

    mock_api_response = {"id" => "assignment_team", "type" => "assignment"}

    stub_request(:post, "https://api.intercom.io/conversations/#{conversation_id}/reply")
      .with(
        body: expected_payload.to_json,
        headers: @config.api_headers
      )
      .to_return(status: 200, body: mock_api_response.to_json)

    result = @client.assign_conversation(conversation_id, admin_id, team_id: team_id)

    assert_equal mock_api_response, result
  end

  def test_assign_conversation_unassign_with_zero
    conversation_id = "conv_123"

    expected_payload = {
      message_type: "assignment",
      type: "admin",
      assignee_id: 0
    }

    mock_api_response = {"id" => "unassignment", "type" => "assignment"}

    stub_request(:post, "https://api.intercom.io/conversations/#{conversation_id}/reply")
      .with(
        body: expected_payload.to_json,
        headers: @config.api_headers
      )
      .to_return(status: 200, body: mock_api_response.to_json)

    result = @client.assign_conversation(conversation_id, "0")

    assert_equal mock_api_response, result
  end

  def test_assign_conversation_unassign_with_integer_zero
    conversation_id = "conv_123"

    expected_payload = {
      message_type: "assignment",
      type: "admin",
      assignee_id: 0
    }

    mock_api_response = {"id" => "unassignment", "type" => "assignment"}

    stub_request(:post, "https://api.intercom.io/conversations/#{conversation_id}/reply")
      .with(
        body: expected_payload.to_json,
        headers: @config.api_headers
      )
      .to_return(status: 200, body: mock_api_response.to_json)

    result = @client.assign_conversation(conversation_id, 0)

    assert_equal mock_api_response, result
  end

  def test_unassign_conversation
    conversation_id = "conv_123"

    expected_payload = {
      message_type: "assignment",
      type: "admin",
      assignee_id: 0
    }

    mock_api_response = {"id" => "unassignment", "type" => "assignment"}

    stub_request(:post, "https://api.intercom.io/conversations/#{conversation_id}/reply")
      .with(
        body: expected_payload.to_json,
        headers: @config.api_headers
      )
      .to_return(status: 200, body: mock_api_response.to_json)

    result = @client.unassign_conversation(conversation_id)

    assert_equal mock_api_response, result
  end

  def test_add_tag
    conversation_id = "conv_123"
    tag_name = "important"

    expected_payload = {
      name: tag_name
    }

    mock_api_response = {"id" => "tag_456", "name" => tag_name}

    stub_request(:post, "https://api.intercom.io/conversations/#{conversation_id}/tags")
      .with(
        body: expected_payload.to_json,
        headers: @config.api_headers
      )
      .to_return(status: 200, body: mock_api_response.to_json)

    result = @client.add_tag(conversation_id, tag_name)

    assert_equal mock_api_response, result
  end

  def test_add_tag_failure
    conversation_id = "conv_123"
    tag_name = "important"

    stub_request(:post, "https://api.intercom.io/conversations/#{conversation_id}/tags")
      .to_return(status: 400, body: {"error" => "Invalid tag"}.to_json)

    result = @client.add_tag(conversation_id, tag_name)

    assert_nil result
  end

  def test_remove_tag
    conversation_id = "conv_123"
    tag_id = "tag_456"

    mock_api_response = {"success" => true}

    stub_request(:delete, "https://api.intercom.io/conversations/#{conversation_id}/tags/#{tag_id}")
      .with(headers: @config.api_headers)
      .to_return(status: 200, body: mock_api_response.to_json)

    result = @client.remove_tag(conversation_id, tag_id)

    assert_equal mock_api_response, result
  end

  def test_remove_tag_failure
    conversation_id = "conv_123"
    tag_id = "tag_456"

    stub_request(:delete, "https://api.intercom.io/conversations/#{conversation_id}/tags/#{tag_id}")
      .to_return(status: 404, body: {"error" => "Tag not found"}.to_json)

    result = @client.remove_tag(conversation_id, tag_id)

    assert_nil result
  end

  def test_update_conversation_state_open
    conversation_id = "conv_123"
    state = "open"

    expected_payload = {
      message_type: state
    }

    mock_api_response = {"id" => "state_update", "state" => state}

    stub_request(:post, "https://api.intercom.io/conversations/#{conversation_id}/reply")
      .with(
        body: expected_payload.to_json,
        headers: @config.api_headers
      )
      .to_return(status: 200, body: mock_api_response.to_json)

    result = @client.update_conversation_state(conversation_id, state)

    assert_equal mock_api_response, result
  end

  def test_update_conversation_state_closed
    conversation_id = "conv_123"
    state = "closed"

    expected_payload = {
      message_type: state
    }

    mock_api_response = {"id" => "state_update", "state" => state}

    stub_request(:post, "https://api.intercom.io/conversations/#{conversation_id}/reply")
      .with(
        body: expected_payload.to_json,
        headers: @config.api_headers
      )
      .to_return(status: 200, body: mock_api_response.to_json)

    result = @client.update_conversation_state(conversation_id, state)

    assert_equal mock_api_response, result
  end

  def test_update_conversation_state_snoozed_with_time
    conversation_id = "conv_123"
    state = "snoozed"
    snoozed_until = Time.new(2024, 12, 25, 10, 0, 0)

    expected_payload = {
      message_type: state,
      snoozed_until: snoozed_until.to_i
    }

    mock_api_response = {"id" => "state_update", "state" => state}

    stub_request(:post, "https://api.intercom.io/conversations/#{conversation_id}/reply")
      .with(
        body: expected_payload.to_json,
        headers: @config.api_headers
      )
      .to_return(status: 200, body: mock_api_response.to_json)

    result = @client.update_conversation_state(conversation_id, state, snoozed_until: snoozed_until)

    assert_equal mock_api_response, result
  end

  def test_update_conversation_state_with_priority
    conversation_id = "conv_123"
    state = "open"
    priority = "priority"

    expected_payload = {
      message_type: state,
      priority: priority
    }

    mock_api_response = {"id" => "state_update", "state" => state, "priority" => priority}

    stub_request(:post, "https://api.intercom.io/conversations/#{conversation_id}/reply")
      .with(
        body: expected_payload.to_json,
        headers: @config.api_headers
      )
      .to_return(status: 200, body: mock_api_response.to_json)

    result = @client.update_conversation_state(conversation_id, state, priority: priority)

    assert_equal mock_api_response, result
  end

  def test_update_conversation_state_priority_only
    conversation_id = "conv_123"
    priority = "not_priority"

    expected_payload = {
      priority: priority
    }

    mock_api_response = {"id" => "state_update", "priority" => priority}

    stub_request(:post, "https://api.intercom.io/conversations/#{conversation_id}/reply")
      .with(
        body: expected_payload.to_json,
        headers: @config.api_headers
      )
      .to_return(status: 200, body: mock_api_response.to_json)

    result = @client.update_conversation_state(conversation_id, nil, priority: priority)

    assert_equal mock_api_response, result
  end

  def test_update_conversation_state_no_changes_returns_true
    conversation_id = "conv_123"

    # No API call should be made
    result = @client.update_conversation_state(conversation_id)

    assert_equal true, result
  end

  def test_update_conversation_state_failure
    conversation_id = "conv_123"
    state = "open"

    stub_request(:post, "https://api.intercom.io/conversations/#{conversation_id}/reply")
      .to_return(status: 400, body: {"error" => "Invalid state"}.to_json)

    result = @client.update_conversation_state(conversation_id, state)

    assert_nil result
  end

  def test_get_conversation
    conversation_id = "conv_123"

    mock_conversation = {
      "id" => conversation_id,
      "type" => "conversation",
      "state" => "open",
      "user" => {"id" => "user_456", "name" => "John Doe"}
    }

    stub_request(:get, "https://api.intercom.io/conversations/#{conversation_id}")
      .with(headers: @config.api_headers)
      .to_return(status: 200, body: mock_conversation.to_json)

    result = @client.get_conversation(conversation_id)

    assert_equal mock_conversation, result
    assert_equal conversation_id, result["id"]
  end

  def test_get_conversation_not_found
    conversation_id = "conv_nonexistent"

    stub_request(:get, "https://api.intercom.io/conversations/#{conversation_id}")
      .to_return(status: 404, body: {"error" => "Conversation not found"}.to_json)

    result = @client.get_conversation(conversation_id)

    assert_nil result
  end

  def test_list_admins
    mock_admins_response = {
      "admins" => [
        {
          "id" => "admin_123",
          "name" => "John Admin",
          "email" => "john@example.com",
          "away_mode_enabled" => false
        },
        {
          "id" => "admin_456",
          "name" => "Jane Admin",
          "email" => "jane@example.com",
          "away_mode_enabled" => true
        }
      ]
    }

    stub_request(:get, "https://api.intercom.io/admins")
      .with(headers: @config.api_headers)
      .to_return(status: 200, body: mock_admins_response.to_json)

    result = @client.list_admins

    assert_equal mock_admins_response, result
    assert_equal 2, result["admins"].length
    assert_equal "admin_123", result["admins"][0]["id"]
    assert_equal "John Admin", result["admins"][0]["name"]
  end

  def test_list_admins_failure
    stub_request(:get, "https://api.intercom.io/admins")
      .to_return(status: 403, body: {"error" => "Forbidden"}.to_json)

    result = @client.list_admins

    assert_nil result
  end

  def test_build_reply_payload_text
    response = [:text, "Hello there!", {}]
    conversation_id = "conv_123"

    expected_payload = {
      message_type: "comment",
      type: "admin",
      admin_id: "test_admin_id",
      body: "Hello there!"
    }

    result = @client.build_reply_payload(response, conversation_id)

    assert_equal expected_payload, result
  end

  def test_build_reply_payload_note
    response = [:note, "Internal note", {}]
    conversation_id = "conv_123"

    expected_payload = {
      message_type: "note",
      type: "admin",
      admin_id: "test_admin_id",
      body: "Internal note"
    }

    result = @client.build_reply_payload(response, conversation_id)

    assert_equal expected_payload, result
  end

  def test_build_reply_payload_unknown_type
    response = [:custom_type, "Some content", {}]
    conversation_id = "conv_123"

    expected_payload = {
      message_type: "comment",
      type: "admin",
      admin_id: "test_admin_id",
      body: "Some content"
    }

    result = @client.build_reply_payload(response, conversation_id)

    assert_equal expected_payload, result
  end

  def test_build_reply_payload_handles_non_string_content
    response = [:text, 12345, {}]
    conversation_id = "conv_123"

    expected_payload = {
      message_type: "comment",
      type: "admin",
      admin_id: "test_admin_id",
      body: "12345"
    }

    result = @client.build_reply_payload(response, conversation_id)

    assert_equal expected_payload, result
  end

  def test_api_request_with_json_parse_error
    conversation_id = "conv_123"
    response = [:text, "Hello", {}]

    stub_request(:post, "https://api.intercom.io/conversations/#{conversation_id}/reply")
      .to_return(status: 200, body: "invalid json {")

    result = @client.send_message(conversation_id, response)

    assert_nil result
  end

  def test_api_request_with_generic_exception
    conversation_id = "conv_123"
    response = [:text, "Hello", {}]

    stub_request(:post, "https://api.intercom.io/conversations/#{conversation_id}/reply")
      .to_raise(StandardError.new("Something went wrong"))

    result = @client.send_message(conversation_id, response)

    assert_nil result
  end

  def test_api_headers_from_config
    expected_headers = {
      "Authorization" => "Bearer test_access_token",
      "Content-Type" => "application/json",
      "Accept" => "application/json",
      "Intercom-Version" => "2.11"
    }

    conversation_id = "conv_123"
    response = [:text, "Hello", {}]

    stub_request(:post, "https://api.intercom.io/conversations/#{conversation_id}/reply")
      .with(headers: expected_headers)
      .to_return(status: 200, body: {"id" => "msg_123"}.to_json)

    result = @client.send_message(conversation_id, response)

    refute_nil result
  end

  private

  def assert_requested_with_headers(stub, expected_headers)
    assert_requested(stub) do |request|
      expected_headers.all? { |key, value| request.headers[key] == value }
    end
  end
end

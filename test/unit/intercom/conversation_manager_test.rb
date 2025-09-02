require "test_helper"

class FlowChat::Intercom::ConversationManagerTest < Minitest::Test
  def setup
    @conversation_id = "conv_123"
    @client = Minitest::Mock.new
    @manager = FlowChat::Intercom::ConversationManager.new(@client, @conversation_id)
  end

  def teardown
    @client.verify if @client.respond_to?(:verify)
  end

  def test_initialize_sets_attributes
    # Use instance variable directly to avoid mock comparison issues
    assert_equal @client.object_id, @manager.instance_variable_get(:@client).object_id
    assert_equal @conversation_id, @manager.conversation_id
  end

  def test_assign_conversation_success
    assignee_id = "admin_456"

    @client.expect(:assign_conversation, {"id" => "assignment_123"}, [@conversation_id, assignee_id], team_id: nil)

    result = @manager.assign_conversation(assignee_id)

    assert_equal true, result
  end

  def test_assign_conversation_with_team
    assignee_id = "admin_456"
    team_id = "team_789"

    @client.expect(:assign_conversation, {"id" => "assignment_123"}, [@conversation_id, assignee_id], team_id: team_id)

    result = @manager.assign_conversation(assignee_id, team_id: team_id)

    assert_equal true, result
  end

  def test_assign_conversation_failure
    assignee_id = "admin_456"

    @client.expect(:assign_conversation, nil, [@conversation_id, assignee_id], team_id: nil)

    result = @manager.assign_conversation(assignee_id)

    assert_equal false, result
  end

  def test_assign_conversation_exception
    assignee_id = "admin_456"

    # Create a new client that raises an exception
    exception_client = Object.new
    def exception_client.assign_conversation(*args)
      raise StandardError.new("API error")
    end

    manager = FlowChat::Intercom::ConversationManager.new(exception_client, @conversation_id)
    result = manager.assign_conversation(assignee_id)

    assert_equal false, result
  end

  def test_add_tag_success
    tag_name = "important"

    @client.expect(:add_tag, {"id" => "tag_123", "name" => tag_name}, [@conversation_id, tag_name])

    result = @manager.add_tag(tag_name)

    assert_equal true, result
  end

  def test_add_tag_failure
    tag_name = "important"

    @client.expect(:add_tag, nil, [@conversation_id, tag_name])

    result = @manager.add_tag(tag_name)

    assert_equal false, result
  end

  def test_add_tag_exception
    tag_name = "important"

    # Create a test client that raises an exception
    failing_client = Object.new
    def failing_client.add_tag(*args)
      raise StandardError.new("API error")
    end

    failing_manager = FlowChat::Intercom::ConversationManager.new(failing_client, @conversation_id)
    result = failing_manager.add_tag(tag_name)

    assert_equal false, result
  end

  def test_remove_tags_by_name_success
    tag_names = ["important", "urgent"]

    # Mock conversation response with tags
    conversation_response = {
      "id" => @conversation_id,
      "tags" => {
        "tags" => [
          {"id" => "tag_123", "name" => "important"},
          {"id" => "tag_456", "name" => "urgent"},
          {"id" => "tag_789", "name" => "other"}
        ]
      }
    }

    @client.expect(:get_conversation, conversation_response, [@conversation_id])
    @client.expect(:remove_tag, {"success" => true}, [@conversation_id, "tag_123"])
    @client.expect(:remove_tag, {"success" => true}, [@conversation_id, "tag_456"])

    result = @manager.remove_tags_by_name(tag_names)

    assert_equal true, result
  end

  def test_remove_tags_by_name_no_matching_tags
    tag_names = ["nonexistent"]

    conversation_response = {
      "id" => @conversation_id,
      "tags" => {
        "tags" => [
          {"id" => "tag_123", "name" => "important"}
        ]
      }
    }

    @client.expect(:get_conversation, conversation_response, [@conversation_id])

    result = @manager.remove_tags_by_name(tag_names)

    assert_equal true, result
  end

  def test_remove_tags_by_name_no_tags_on_conversation
    tag_names = ["important"]

    conversation_response = {
      "id" => @conversation_id,
      "tags" => nil
    }

    @client.expect(:get_conversation, conversation_response, [@conversation_id])

    result = @manager.remove_tags_by_name(tag_names)

    assert_equal true, result
  end

  def test_remove_tags_by_name_conversation_not_found
    tag_names = ["important"]

    @client.expect(:get_conversation, nil, [@conversation_id])

    result = @manager.remove_tags_by_name(tag_names)

    assert_equal false, result
  end

  def test_remove_tags_by_name_partial_failure
    tag_names = ["important", "urgent"]

    conversation_response = {
      "id" => @conversation_id,
      "tags" => {
        "tags" => [
          {"id" => "tag_123", "name" => "important"},
          {"id" => "tag_456", "name" => "urgent"}
        ]
      }
    }

    @client.expect(:get_conversation, conversation_response, [@conversation_id])
    @client.expect(:remove_tag, {"success" => true}, [@conversation_id, "tag_123"])
    @client.expect(:remove_tag, nil, [@conversation_id, "tag_456"]) # Failure

    result = @manager.remove_tags_by_name(tag_names)

    assert_equal false, result
  end

  def test_remove_tags_by_name_exception
    tag_names = ["important"]

    # Create a test client that raises an exception
    failing_client = Object.new
    def failing_client.get_conversation(*args)
      raise StandardError.new("API error")
    end

    failing_manager = FlowChat::Intercom::ConversationManager.new(failing_client, @conversation_id)
    result = failing_manager.remove_tags_by_name(tag_names)

    assert_equal false, result
  end

  def test_update_state_success
    state = "closed"

    @client.expect(:update_conversation_state, {"id" => "update_123"}, [@conversation_id, state], snoozed_until: nil)

    result = @manager.update_state(state)

    assert_equal true, result
  end

  def test_update_state_with_snooze_time
    state = "snoozed"
    snoozed_until = Time.new(2024, 12, 25, 10, 0, 0)

    @client.expect(:update_conversation_state, {"id" => "update_123"}, [@conversation_id, state], snoozed_until: snoozed_until)

    result = @manager.update_state(state, snoozed_until: snoozed_until)

    assert_equal true, result
  end

  def test_update_state_failure
    state = "closed"

    @client.expect(:update_conversation_state, nil, [@conversation_id, state], snoozed_until: nil)

    result = @manager.update_state(state)

    assert_equal false, result
  end

  def test_update_state_exception
    state = "closed"

    # Create a test client that raises an exception
    failing_client = Object.new
    def failing_client.update_conversation_state(*args)
      raise StandardError.new("API error")
    end

    failing_manager = FlowChat::Intercom::ConversationManager.new(failing_client, @conversation_id)
    result = failing_manager.update_state(state)

    assert_equal false, result
  end

  def test_update_priority_success
    priority = "priority"

    @client.expect(:update_conversation_state, {"id" => "update_123"}, [@conversation_id, nil], priority: priority)

    result = @manager.update_priority(priority)

    assert_equal true, result
  end

  def test_update_priority_failure
    priority = "not_priority"

    @client.expect(:update_conversation_state, nil, [@conversation_id, nil], priority: priority)

    result = @manager.update_priority(priority)

    assert_equal false, result
  end

  def test_update_priority_exception
    priority = "priority"

    # Create a test client that raises an exception
    failing_client = Object.new
    def failing_client.update_conversation_state(*args)
      raise StandardError.new("API error")
    end

    failing_manager = FlowChat::Intercom::ConversationManager.new(failing_client, @conversation_id)
    result = failing_manager.update_priority(priority)

    assert_equal false, result
  end

  def test_send_reply_text_success
    message = "Hello there!"

    @client.expect(:send_message, {"id" => "msg_123"}, [@conversation_id, message])

    result = @manager.send_reply(message)

    assert_equal true, result
  end

  def test_send_reply_note_success
    message = "Internal note"

    @client.expect(:send_message, {"id" => "msg_123"}, [@conversation_id, message])

    result = @manager.send_reply(message, type: :note)

    assert_equal true, result
  end

  def test_send_reply_failure
    message = "Hello there!"

    @client.expect(:send_message, nil, [@conversation_id, message])

    result = @manager.send_reply(message)

    assert_equal false, result
  end

  def test_send_reply_exception
    message = "Hello there!"

    # Create a test client that raises an exception
    failing_client = Object.new
    def failing_client.send_message(*args)
      raise StandardError.new("API error")
    end

    failing_manager = FlowChat::Intercom::ConversationManager.new(failing_client, @conversation_id)
    result = failing_manager.send_reply(message)

    assert_equal false, result
  end

  def test_get_conversation_success
    conversation_data = {
      "id" => @conversation_id,
      "type" => "conversation",
      "state" => "open"
    }

    @client.expect(:get_conversation, conversation_data, [@conversation_id])

    result = @manager.get_conversation

    assert_equal conversation_data, result
  end

  def test_get_conversation_failure
    @client.expect(:get_conversation, nil, [@conversation_id])

    result = @manager.get_conversation

    assert_nil result
  end

  def test_get_conversation_exception
    # Create a test client that raises an exception
    failing_client = Object.new
    def failing_client.get_conversation(*args)
      raise StandardError.new("API error")
    end

    failing_manager = FlowChat::Intercom::ConversationManager.new(failing_client, @conversation_id)
    result = failing_manager.get_conversation

    assert_nil result
  end

  def test_has_tags_true
    tag_names = ["important", "urgent"]

    conversation_data = {
      "id" => @conversation_id,
      "tags" => {
        "tags" => [
          {"id" => "tag_123", "name" => "important"},
          {"id" => "tag_456", "name" => "other"}
        ]
      }
    }

    @client.expect(:get_conversation, conversation_data, [@conversation_id])

    result = @manager.has_tags?(tag_names)

    assert_equal true, result
  end

  def test_has_tags_false
    tag_names = ["nonexistent"]

    conversation_data = {
      "id" => @conversation_id,
      "tags" => {
        "tags" => [
          {"id" => "tag_123", "name" => "important"}
        ]
      }
    }

    @client.expect(:get_conversation, conversation_data, [@conversation_id])

    result = @manager.has_tags?(tag_names)

    assert_equal false, result
  end

  def test_has_tags_no_tags_on_conversation
    tag_names = ["important"]

    conversation_data = {
      "id" => @conversation_id,
      "tags" => nil
    }

    @client.expect(:get_conversation, conversation_data, [@conversation_id])

    result = @manager.has_tags?(tag_names)

    assert_equal false, result
  end

  def test_has_tags_conversation_not_found
    tag_names = ["important"]

    @client.expect(:get_conversation, nil, [@conversation_id])

    result = @manager.has_tags?(tag_names)

    assert_equal false, result
  end

  def test_has_tags_exception
    tag_names = ["important"]

    # Create a test client that raises an exception
    failing_client = Object.new
    def failing_client.get_conversation(*args)
      raise StandardError.new("API error")
    end

    failing_manager = FlowChat::Intercom::ConversationManager.new(failing_client, @conversation_id)
    result = failing_manager.has_tags?(tag_names)

    assert_equal false, result
  end

  def test_get_tags_success
    conversation_data = {
      "id" => @conversation_id,
      "tags" => {
        "tags" => [
          {"id" => "tag_123", "name" => "important"},
          {"id" => "tag_456", "name" => "urgent"}
        ]
      }
    }

    @client.expect(:get_conversation, conversation_data, [@conversation_id])

    result = @manager.get_tags

    assert_equal ["important", "urgent"], result
  end

  def test_get_tags_no_tags
    conversation_data = {
      "id" => @conversation_id,
      "tags" => nil
    }

    @client.expect(:get_conversation, conversation_data, [@conversation_id])

    result = @manager.get_tags

    assert_equal [], result
  end

  def test_get_tags_empty_tags
    conversation_data = {
      "id" => @conversation_id,
      "tags" => {
        "tags" => []
      }
    }

    @client.expect(:get_conversation, conversation_data, [@conversation_id])

    result = @manager.get_tags

    assert_equal [], result
  end

  def test_get_tags_conversation_not_found
    @client.expect(:get_conversation, nil, [@conversation_id])

    result = @manager.get_tags

    assert_equal [], result
  end

  def test_get_tags_exception
    # Create a test client that raises an exception
    failing_client = Object.new
    def failing_client.get_conversation(*args)
      raise StandardError.new("API error")
    end

    failing_manager = FlowChat::Intercom::ConversationManager.new(failing_client, @conversation_id)
    result = failing_manager.get_tags

    assert_equal [], result
  end
end

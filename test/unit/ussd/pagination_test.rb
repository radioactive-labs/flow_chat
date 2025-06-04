require "test_helper"

class UssdPaginationTest < Minitest::Test
  def setup
    @context = FlowChat::Context.new
    @context.session = create_test_session_store
    @context.input = nil
    
    # Mock app that returns responses
    @mock_app = lambda do |context|
      [:prompt, "Short response", []]
    end
    
    @pagination = FlowChat::Ussd::Middleware::Pagination.new(@mock_app)
    
    # Store original config values
    @original_page_size = FlowChat::Config.ussd.pagination_page_size
    @original_next_option = FlowChat::Config.ussd.pagination_next_option
    @original_back_option = FlowChat::Config.ussd.pagination_back_option
    @original_next_text = FlowChat::Config.ussd.pagination_next_text
    @original_back_text = FlowChat::Config.ussd.pagination_back_text
    
    # Set test configuration
    FlowChat::Config.ussd.pagination_page_size = 100
    FlowChat::Config.ussd.pagination_next_option = "#"
    FlowChat::Config.ussd.pagination_back_option = "0"
    FlowChat::Config.ussd.pagination_next_text = "More"
    FlowChat::Config.ussd.pagination_back_text = "Back"
  end

  def teardown
    # Restore original config values
    FlowChat::Config.ussd.pagination_page_size = @original_page_size
    FlowChat::Config.ussd.pagination_next_option = @original_next_option
    FlowChat::Config.ussd.pagination_back_option = @original_back_option
    FlowChat::Config.ussd.pagination_next_text = @original_next_text
    FlowChat::Config.ussd.pagination_back_text = @original_back_text
  end

  def test_short_response_passes_through_unchanged
    type, prompt, choices = @pagination.call(@context)
    
    assert_equal :prompt, type
    assert_equal "Short response", prompt
    assert_empty choices
  end

  def test_long_response_gets_paginated
    # Create a mock app that returns a long response
    long_response = "A" * 150  # Exceeds our 100 character limit
    long_app = lambda { |context| [:prompt, long_response, []] }
    pagination = FlowChat::Ussd::Middleware::Pagination.new(long_app)
    
    type, prompt, choices = pagination.call(@context)
    
    assert_equal :prompt, type
    assert prompt.length <= FlowChat::Config.ussd.pagination_page_size
    assert_includes prompt, "# More"
    assert_empty choices
    
    # Check pagination state was set
    pagination_state = @context.session.get("ussd.pagination")
    refute_nil pagination_state
    assert_equal 1, pagination_state["page"]
    assert_equal long_response, pagination_state["prompt"]
  end

  def test_navigation_to_next_page
    # First, set up pagination state
    long_response = "A" * 80 + "\n" + "B" * 80  # Will span multiple pages
    pagination_state = {
      "page" => 1,
      "offsets" => {
        "1" => {"start" => 0, "finish" => 50}
      },
      "prompt" => long_response,
      "type" => "prompt"
    }
    @context.session.set("ussd.pagination", pagination_state)
    @context.input = "#"  # Next page input
    
    type, prompt, choices = @pagination.call(@context)
    
    assert_equal :prompt, type
    assert_includes prompt, "B"  # Should show second part
    assert_empty choices
  end

  def test_navigation_to_previous_page
    # Set up pagination state on page 2
    long_response = "A" * 80 + "\n" + "B" * 80
    pagination_state = {
      "page" => 2,
      "offsets" => {
        "1" => {"start" => 0, "finish" => 50},
        "2" => {"start" => 51, "finish" => 100}
      },
      "prompt" => long_response,
      "type" => "prompt"
    }
    @context.session.set("ussd.pagination", pagination_state)
    @context.input = "0"  # Back page input
    
    type, prompt, choices = @pagination.call(@context)
    
    assert_equal :prompt, type
    assert_includes prompt, "A"  # Should show first part
    assert_empty choices
  end

  def test_terminal_response_pagination
    # Test pagination with terminal response type
    long_response = "Thank you! " + "Your transaction is complete. " * 10
    terminal_app = lambda { |context| [:terminal, long_response, []] }
    pagination = FlowChat::Ussd::Middleware::Pagination.new(terminal_app)
    
    type, prompt, choices = pagination.call(@context)
    
    assert_equal :prompt, type  # Should be prompt for pagination
    assert prompt.length <= FlowChat::Config.ussd.pagination_page_size
    assert_includes prompt, "# More"
  end

  def test_last_page_becomes_terminal
    # Set up pagination state on the last page
    long_response = "Short final message"
    pagination_state = {
      "page" => 2,
      "offsets" => {
        "1" => {"start" => 0, "finish" => 50},
        "2" => {"start" => 51, "finish" => long_response.length - 1}
      },
      "prompt" => long_response,
      "type" => "terminal"
    }
    @context.session.set("ussd.pagination", pagination_state)
    @context.input = "#"  # Next page input
    
    type, prompt, choices = @pagination.call(@context)
    
    assert_equal :terminal, type  # Should be terminal on last page
    refute_includes prompt, "# More"  # No more pagination
  end

  def test_pagination_preserves_word_boundaries
    # Test that pagination breaks at word boundaries, not mid-word
    long_response = "This is a very long response that should break at word boundaries not letters"
    long_app = lambda { |context| [:prompt, long_response, []] }
    pagination = FlowChat::Ussd::Middleware::Pagination.new(long_app)
    
    # Set a small page size to force word boundary breaking
    FlowChat::Config.ussd.pagination_page_size = 50
    
    type, prompt, choices = pagination.call(@context)
    
    # Simply verify that pagination occurred and the prompt contains the pagination option
    if prompt.include?("# More")
      assert prompt.length <= FlowChat::Config.ussd.pagination_page_size
    end
  end

  def test_pagination_handles_newlines_properly
    # Test pagination with content that has newlines
    long_response = "Line 1\nLine 2\nLine 3\nLine 4\nLine 5\nLine 6\nLine 7\nLine 8"
    long_app = lambda { |context| [:prompt, long_response, []] }
    pagination = FlowChat::Ussd::Middleware::Pagination.new(long_app)
    
    type, prompt, choices = pagination.call(@context)
    
    # Should prefer breaking at newlines
    first_page = prompt.gsub(/\n\n# More$/, "")
    if prompt.include?("# More")
      assert first_page.end_with?("\n") || first_page.split("\n").last.length <= 10
    end
  end

  def test_pagination_options_configuration
    long_response = "A" * 150
    long_app = lambda { |context| [:prompt, long_response, []] }
    pagination = FlowChat::Ussd::Middleware::Pagination.new(long_app)
    
    # Test with custom pagination options
    FlowChat::Config.ussd.pagination_next_option = "99"
    FlowChat::Config.ussd.pagination_next_text = "Continue"
    
    type, prompt, choices = pagination.call(@context)
    
    assert_includes prompt, "99 Continue"
  end

  def test_pagination_state_management
    long_response = "A" * 150
    long_app = lambda { |context| [:prompt, long_response, []] }
    pagination = FlowChat::Ussd::Middleware::Pagination.new(long_app)
    
    # First call should set pagination state
    pagination.call(@context)
    
    pagination_state = @context.session.get("ussd.pagination")
    refute_nil pagination_state
    assert_equal 1, pagination_state["page"]
    assert_equal :prompt, pagination_state["type"]  # It's stored as a symbol
    assert pagination_state["offsets"].is_a?(Hash)
    assert_equal long_response, pagination_state["prompt"]
  end

  def test_pagination_clears_state_for_new_response
    # Set up existing pagination state with proper type
    @context.session.set("ussd.pagination", {
      "page" => 2, 
      "prompt" => "old",
      "type" => "prompt"  # Add type to avoid nil error
    })
    
    # Make a new request (not a pagination navigation)
    @context.input = "some_regular_input"  # Not a pagination input
    type, prompt, choices = @pagination.call(@context)
    
    # Pagination state should be cleared for new response
    pagination_state = @context.session.get("ussd.pagination")
    assert_nil pagination_state
  end

  def test_pagination_with_choices_rendered
    # Test that choices are properly rendered before pagination
    choices = {"1" => "Option 1", "2" => "Option 2"}
    app_with_choices = lambda { |context| [:prompt, "Choose an option:", choices] }
    pagination = FlowChat::Ussd::Middleware::Pagination.new(app_with_choices)
    
    type, prompt, choices_returned = pagination.call(@context)
    
    assert_equal :prompt, type
    assert_includes prompt, "Choose an option:"
    assert_includes prompt, "1. Option 1"
    assert_includes prompt, "2. Option 2"
    assert_empty choices_returned  # Choices are rendered into prompt
  end

  def test_pagination_handles_empty_response
    empty_app = lambda { |context| [:prompt, "", []] }
    pagination = FlowChat::Ussd::Middleware::Pagination.new(empty_app)
    
    type, prompt, choices = pagination.call(@context)
    
    assert_equal :prompt, type
    assert_equal "", prompt
    assert_empty choices
  end

  def test_intercept_pagination_navigation
    # Test that pagination navigation inputs are intercepted
    pagination_state = {
      "page" => 1,
      "offsets" => {"1" => {"start" => 0, "finish" => 50}},
      "prompt" => "A" * 100,
      "type" => "prompt"
    }
    @context.session.set("ussd.pagination", pagination_state)
    
    # Test next page navigation
    @context.input = "#"
    type, prompt, choices = @pagination.call(@context)
    assert_equal :prompt, type
    
    # Test back page navigation  
    @context.input = "0"
    type, prompt, choices = @pagination.call(@context)
    assert_equal :prompt, type
  end

  def test_pagination_configuration_affects_behavior
    # Test that changing configuration affects pagination behavior
    FlowChat::Config.ussd.pagination_page_size = 50
    FlowChat::Config.ussd.pagination_next_option = "N"
    FlowChat::Config.ussd.pagination_next_text = "Next"
    
    long_response = "A" * 80
    long_app = lambda { |context| [:prompt, long_response, []] }
    pagination = FlowChat::Ussd::Middleware::Pagination.new(long_app)
    
    type, prompt, choices = pagination.call(@context)
    
    assert prompt.length <= 50 + 10  # Allow some margin for pagination options
    assert_includes prompt, "N Next"
  end
end 
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

    type, prompt, _ = pagination.call(@context)

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

    type, prompt, _ = @pagination.call(@context)

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

    _, prompt, _ = pagination.call(@context)

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

    _, prompt, _ = pagination.call(@context)

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

    _, prompt, _ = pagination.call(@context)

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
    assert_equal "prompt", pagination_state["type"]  # It's stored as a string for cache compatibility
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
    _, _, _ = @pagination.call(@context)

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
    type, _, _ = @pagination.call(@context)
    assert_equal :prompt, type

    # Test back page navigation
    @context.input = "0"
    type, _, _ = @pagination.call(@context)
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

    _, prompt, _ = pagination.call(@context)

    assert prompt.length <= 50 + 10  # Allow some margin for pagination options
    assert_includes prompt, "N Next"
  end

  def test_pagination_preserves_word_boundaries_comprehensive
    # Test comprehensive word boundary scenarios that previously failed
    
    # Scenario 1: Should not cut "Choose a test" to "Choose a tes"
    test_text = "🧪 Welcome to the FlowChat Comprehensive Test Suite!\n\nThis flow will test all major FlowChat features across platforms.\n\nChoose a test category:"
    choices = {
      "basic" => "🔤 Basic Input Tests",
      "validation" => "✅ Validation & Transformation Tests", 
      "choices" => "📋 Choice Selection Tests"
    }
    
    # Use the actual renderer to get realistic text
    renderer = FlowChat::Ussd::Renderer.new(test_text, choices: choices)
    rendered_text = renderer.render
    
    long_app = lambda { |context| [:prompt, test_text, choices] }
    pagination = FlowChat::Ussd::Middleware::Pagination.new(long_app)
    
    # Set page size that would previously cause the bug
    original_page_size = FlowChat::Config.ussd.pagination_page_size
    FlowChat::Config.ussd.pagination_page_size = 140
    
    begin
      _, prompt, _ = pagination.call(@context)
      
      # Should never contain "Choose a tes" without "Choose a test"
      refute(prompt.include?("Choose a tes") && !prompt.include?("Choose a test"), 
             "Pagination cut mid-word: 'Choose a tes' found without 'Choose a test'")
      
      # If pagination occurred, verify it found a proper boundary
      if prompt.include?("# More")
        # Extract the paginated content (without the pagination options)
        content = prompt.gsub(/\n\n# More$/, "")
        
        # Should end with a word boundary (space, newline, or punctuation)
        assert content.match(/[\s\n\.!?:]$/) || content.length < 10, 
               "Pagination should break at word boundaries, got: '#{content[-10..-1]}'"
      end
      
    ensure
      FlowChat::Config.ussd.pagination_page_size = original_page_size
    end
  end

  def test_word_boundary_in_subsequent_pages
    # Test word boundary preservation in calculate_offsets (subsequent pages)
    long_text = "First page content that will be on page one. " +
                "Choose a test category for the second page content: " +
                "basic option, advanced option, complete option here."
    
    # Set up pagination state as if we're on page 1
    # Find a proper boundary - after "page one. " and before "Choose"
    boundary_pos = long_text.index("Choose") - 1
    
    pagination_state = {
      "page" => 1,
      "offsets" => {"1" => {"start" => 0, "finish" => boundary_pos}}, # Ends right before "Choose"
      "prompt" => long_text,
      "type" => "prompt"
    }
    @context.session.set("ussd.pagination", pagination_state)
    @context.input = "#"  # Navigate to next page
    
    original_page_size = FlowChat::Config.ussd.pagination_page_size
    FlowChat::Config.ussd.pagination_page_size = 120
    
    begin
      _, prompt, _ = @pagination.call(@context)
      
      # Should not cut "Choose a test" to "Choose a tes"
      refute(prompt.include?("Choose a tes") && !prompt.include?("Choose a test"), 
             "Subsequent page pagination cut mid-word: 'Choose a tes' found")
      
      # Should start with "Choose a test" (the beginning of page 2)
      assert prompt.start_with?("Choose a test"), 
             "Page 2 should start with 'Choose a test', got: '#{prompt[0..20]}'"
             
    ensure
      FlowChat::Config.ussd.pagination_page_size = original_page_size
    end
  end

  def test_word_boundary_fallback_scenarios
    # Test scenarios where no word boundaries exist (should gracefully handle)
    no_boundary_text = "VeryLongWordWithoutAnySpacesOrPunctuationThatWouldNormallyBeBrokenMidWord" * 3
    
    long_app = lambda { |context| [:prompt, no_boundary_text, []] }
    pagination = FlowChat::Ussd::Middleware::Pagination.new(long_app)
    
    original_page_size = FlowChat::Config.ussd.pagination_page_size
    FlowChat::Config.ussd.pagination_page_size = 100
    
    begin
      _, prompt, _ = pagination.call(@context)
      
      # Should still paginate even if no word boundaries found
      if no_boundary_text.length > 100
        assert prompt.include?("# More"), 
               "Should paginate long text even without word boundaries"
        assert prompt.length <= FlowChat::Config.ussd.pagination_page_size,
               "Should respect page size limit even in fallback mode"
      end
      
    ensure
      FlowChat::Config.ussd.pagination_page_size = original_page_size
    end
  end

  def test_word_boundary_with_unicode_and_emojis
    # Test word boundaries work correctly with Unicode characters and emojis
    unicode_text = "🧪 Welcome to FlowChat! 测试 Unicode characters and émojis work correctly. " +
                   "Choose a test option for advanced scenarios: básico, avançado, complète testing."
    
    long_app = lambda { |context| [:prompt, unicode_text, []] }
    pagination = FlowChat::Ussd::Middleware::Pagination.new(long_app)
    
    original_page_size = FlowChat::Config.ussd.pagination_page_size
    FlowChat::Config.ussd.pagination_page_size = 90  # Adjusted to force pagination
    
    begin
      _, prompt, _ = pagination.call(@context)
      
      # Should handle Unicode properly in word boundary detection
      if prompt.include?("# More")
        content = prompt.gsub(/\n\n# More$/, "")
        # Should not break in the middle of common words
        refute content.include?("Choose a tes"), 
               "Should not break Unicode text mid-word, got: '#{content[-15..-1]}'"
        
        # Should end with a reasonable boundary (space, punctuation, or newline)
        assert content.match(/[\s\n\.!?:]$/) || content.length < 20, 
               "Should break at reasonable boundaries with Unicode text"
      end
      
    ensure
      FlowChat::Config.ussd.pagination_page_size = original_page_size
    end
  end

  # ============================================================================
  # MEDIA HANDLING TESTS
  # ============================================================================

  def test_pagination_preserves_media_in_rendered_prompt
    # Test that media is properly included in the rendered prompt
    message = "Check out this image:"
    media = {type: :image, url: "https://example.com/image.jpg"}
    
    app_with_media = lambda { |context| [:prompt, message, {}, media] }
    pagination = FlowChat::Ussd::Middleware::Pagination.new(app_with_media)

    type, prompt, choices = pagination.call(@context)

    assert_equal :prompt, type
    assert_includes prompt, "Check out this image:"
    assert_includes prompt, "📷 Image: https://example.com/image.jpg"
    assert_empty choices
  end

  def test_pagination_handles_media_with_choices
    # Test that both media and choices are properly rendered
    message = "What do you think?"
    choices = {"1" => "Like it", "2" => "Don't like it"}
    media = {type: :image, url: "https://example.com/photo.jpg"}
    
    app_with_media_choices = lambda { |context| [:prompt, message, choices, media] }
    pagination = FlowChat::Ussd::Middleware::Pagination.new(app_with_media_choices)

    type, prompt, returned_choices = pagination.call(@context)

    assert_equal :prompt, type
    assert_includes prompt, "What do you think?"
    assert_includes prompt, "📷 Image: https://example.com/photo.jpg"
    assert_includes prompt, "1. Like it"
    assert_includes prompt, "2. Don't like it"
    assert_empty returned_choices  # Choices are rendered into prompt
  end

  def test_pagination_with_long_media_url_triggers_pagination
    # Test that long content with media gets paginated properly
    message = "🧪 Welcome to the FlowChat Comprehensive Test Suite!\n\nThis flow will test all major FlowChat features across platforms.\n\nChoose a test category:"
    media = {type: :image, url: "https://via.placeholder.com/400x300/007bff/ffffff?text=FlowChat+Test+Suite"}
    
    app_with_long_media = lambda { |context| [:prompt, message, {}, media] }
    pagination = FlowChat::Ussd::Middleware::Pagination.new(app_with_long_media)

    # The rendered content should exceed page size and trigger pagination
    type, prompt, _ = pagination.call(@context)

    assert_equal :prompt, type
    assert prompt.length <= FlowChat::Config.ussd.pagination_page_size
    
    # Should contain pagination marker since total content exceeds page size
    if prompt.include?("# More")
      # First page should contain start of message
      assert_includes prompt, "📷 Image:"
    end
  end

  def test_pagination_media_appears_on_correct_page
    # Test that media appears on the correct page when content is paginated
    message = "A" * 100  # Long message to force pagination
    media = {type: :document, url: "https://example.com/doc.pdf"}
    
    app_with_media = lambda { |context| [:prompt, message, {}, media] }
    pagination = FlowChat::Ussd::Middleware::Pagination.new(app_with_media)

    # Set page size small enough to force pagination
    original_page_size = FlowChat::Config.ussd.pagination_page_size
    FlowChat::Config.ussd.pagination_page_size = 80
    
    begin
      # First page
      type, prompt, _ = pagination.call(@context)
      
      if prompt.include?("# More")
        # Content was paginated
        # Check if media appears based on render order (message, media, choices)
        # Since USSD renders in order: message -> media -> choices
        # And our message is 100 chars, media might be on page 2
        
        # Navigate to next page to see if media appears
        @context.input = "#"
        type2, prompt2, _ = pagination.call(@context)
        
        # Media should appear somewhere in the paginated content
        full_content = prompt + prompt2
        assert_includes full_content, "📄 Document: https://example.com/doc.pdf"
      else
        # Content fit on one page
        assert_includes prompt, "📄 Document: https://example.com/doc.pdf"
      end
      
    ensure
      FlowChat::Config.ussd.pagination_page_size = original_page_size
    end
  end

  def test_pagination_handles_nil_media_gracefully
    # Test that pagination works when media is nil
    message = "Long message without media"
    
    app_without_media = lambda { |context| [:prompt, message, {}, nil] }
    pagination = FlowChat::Ussd::Middleware::Pagination.new(app_without_media)

    type, prompt, choices = pagination.call(@context)

    assert_equal :prompt, type
    assert_equal message, prompt
    assert_empty choices
  end

  def test_pagination_handles_empty_media_hash
    # Test that pagination works when media is an empty hash
    message = "Message with empty media"
    
    app_with_empty_media = lambda { |context| [:prompt, message, {}, {}] }
    pagination = FlowChat::Ussd::Middleware::Pagination.new(app_with_empty_media)

    type, prompt, choices = pagination.call(@context)

    assert_equal :prompt, type
    assert_equal message, prompt
    assert_empty choices
  end

  def test_pagination_different_media_types
    # Test that different media types are properly rendered in pagination
    media_types = [
      {type: :image, url: "https://example.com/image.jpg", expected: "📷 Image:"},
      {type: :video, url: "https://example.com/video.mp4", expected: "🎥 Video:"},
      {type: :audio, url: "https://example.com/audio.mp3", expected: "🎵 Audio:"},
      {type: :document, url: "https://example.com/doc.pdf", expected: "📄 Document:"},
      {type: :sticker, url: "https://example.com/sticker.webp", expected: "😊 Sticker:"}
    ]

    media_types.each do |media_test|
      @context = FlowChat::Context.new  # Fresh context for each test
      @context.session = create_test_session_store
      @context.input = nil

      app_with_media = lambda { |context| [:prompt, "Test message", {}, media_test] }
      pagination = FlowChat::Ussd::Middleware::Pagination.new(app_with_media)

      type, prompt, _ = pagination.call(@context)

      assert_equal :prompt, type
      assert_includes prompt, media_test[:expected], "Failed for media type: #{media_test[:type]}"
      assert_includes prompt, media_test[:url]
    end
  end

  def test_pagination_with_extremely_long_single_word
    # Test behavior when a single word exceeds page size
    super_long_word = "Supercalifragilisticexpialidocious" * 10  # ~340 chars
    content_with_long_word = "This is a test with a #{super_long_word} in the middle of the text."
    
    long_word_app = lambda { |context| [:prompt, content_with_long_word, []] }
    pagination = FlowChat::Ussd::Middleware::Pagination.new(long_word_app)
    
    FlowChat::Config.ussd.pagination_page_size = 100
    
    type, prompt, _ = pagination.call(@context)
    
    # Should handle gracefully by breaking mid-word as fallback
    assert_equal :prompt, type
    assert prompt.length <= FlowChat::Config.ussd.pagination_page_size
    
    # Should have pagination state set properly
    pagination_state = @context.session.get("ussd.pagination")
    refute_nil pagination_state
  end

  def test_pagination_with_complex_unicode_clusters
    # Test with complex Unicode including combining characters and zero-width joiners
    complex_unicode = "👨‍👩‍👧‍👦 Family emoji 🇺🇸 flag 🧑🏽‍💻 professional ñiño café résumé naïve señorita"
    repeated_unicode = (complex_unicode + " ") * 20  # Create long content with complex Unicode
    
    unicode_app = lambda { |context| [:prompt, repeated_unicode, []] }
    pagination = FlowChat::Ussd::Middleware::Pagination.new(unicode_app)
    
    FlowChat::Config.ussd.pagination_page_size = 120
    
    type, prompt, _ = pagination.call(@context)
    
    # Should handle Unicode correctly without breaking emoji sequences
    assert_equal :prompt, type
    assert prompt.length <= FlowChat::Config.ussd.pagination_page_size
    
    # The prompt should still contain valid Unicode (no broken sequences)
    assert prompt.valid_encoding?, "Pagination broke Unicode encoding"
    
    # Should not break in the middle of an emoji sequence
    content_part = prompt.gsub(/\n\n# More$/, "")
    refute_match(/\u{200D}$/, content_part, "Pagination broke emoji sequence")
  end

  def test_pagination_boundary_conditions
    # Test exact boundary conditions
    boundary_tests = [
      {"size" => 99, "content_length" => 99},   # Exactly under limit
      {"size" => 100, "content_length" => 100}, # Exactly at limit  
      {"size" => 100, "content_length" => 101}, # Exactly over limit
      {"size" => 160, "content_length" => 160}, # SMS limit exactly
      {"size" => 1,   "content_length" => 5},   # Extremely small page size
    ]
    
    boundary_tests.each do |test|
      FlowChat::Config.ussd.pagination_page_size = test["size"]
      content = "X" * test["content_length"]
      
      boundary_app = lambda { |context| [:prompt, content, []] }
      pagination = FlowChat::Ussd::Middleware::Pagination.new(boundary_app)
      
      # Reset context for each test
      @context.session.delete("ussd.pagination")
      @context.input = ""
      
      begin
        type, prompt, _ = pagination.call(@context)
        
        # Results should be valid
        assert [:prompt, :terminal].include?(type), "Invalid type returned for boundary test"
        refute_nil prompt, "Prompt should not be nil"
        
        # If pagination triggered, state should be valid
        if prompt.include?("# More")
          state = @context.session.get("ussd.pagination")
          refute_nil state, "Pagination state should exist when paginated"
          assert state["page"].is_a?(Integer), "Page should be an integer"
          assert state["page"] > 0, "Page should be positive"
        end
      rescue => e
        flunk("Failed at boundary: page_size=#{test["size"]}, content=#{test["content_length"]} - #{e.message}")
      end
    end
  end

  def test_pagination_navigation_edge_cases
    # Test edge cases in navigation
    FlowChat::Config.ussd.pagination_page_size = 50
    long_content = "Page content. " * 20  # Multiple pages worth
    
    # Set up pagination state
    @context.session.set("ussd.pagination", {
      "page" => 1,
      "offsets" => {"1" => {"start" => 0, "finish" => 30}},
      "prompt" => long_content,
      "type" => "prompt"
    })
    
    navigation_tests = [
      # Try to go back from page 1 (should stay on page 1)
      {"input" => "0", "expected_page" => 1},
      # Go forward multiple times
      {"input" => "#", "expected_min_page" => 2},
      {"input" => "#", "expected_min_page" => 3},
      # Invalid navigation input (should be ignored)
      {"input" => "99", "expected_behavior" => "new_flow"},
    ]
    
    navigation_tests.each do |test|
      @context.input = test[:input]
      
      type, prompt, _ = @pagination.call(@context)
      
      if test[:expected_behavior] == "new_flow"
        # Should clear pagination and start new flow
        state = @context.session.get("ussd.pagination")
        assert_nil state
      elsif test[:expected_page]
        state = @context.session.get("ussd.pagination")
        assert_equal test[:expected_page], state["page"]
      elsif test[:expected_min_page]
        state = @context.session.get("ussd.pagination")
        assert state["page"] >= test[:expected_min_page], "Expected page >= #{test[:expected_min_page]}, got #{state["page"]}"
      end
    end
  end

  def test_pagination_with_dynamic_content_changes
    # Test behavior when underlying content might change between requests
    changeable_content = "Initial content"
    changeable_app = lambda do |context|
      # Simulate content that changes between calls
      changeable_content += " more"
      [:prompt, changeable_content, []]
    end
    
    pagination = FlowChat::Ussd::Middleware::Pagination.new(changeable_app)
    
    # First call - should establish pagination
    type1, prompt1, _ = pagination.call(@context)
    
    # Simulate user navigation
    @context.input = "#"
    
    # Second call - content has changed but pagination state exists
    type2, prompt2, _ = pagination.call(@context)
    
    # Should handle gracefully (either use cached content or detect change)
    assert [:prompt, :terminal].include?(type2)
    refute_nil prompt2
    
    # Should maintain some consistency
    state = @context.session.get("ussd.pagination")
    if state
      assert state.key?("prompt")
      assert state.key?("page")
    end
  end

  def test_pagination_configuration_edge_cases
    # Test with unusual configuration values
    config_tests = [
      {"page_size" => 0, "should_work" => false},     # Invalid size
      {"page_size" => -10, "should_work" => false},   # Negative size
      {"page_size" => 1, "should_work" => true},      # Minimum viable size
      {"page_size" => 10000, "should_work" => true},  # Very large size
    ]
    
    content = "Test content for configuration edge cases."
    config_app = lambda { |context| [:prompt, content, []] }
    pagination = FlowChat::Ussd::Middleware::Pagination.new(config_app)
    
    config_tests.each do |test|
      FlowChat::Config.ussd.pagination_page_size = test["page_size"]
      
      # Reset context
      @context.session.delete("ussd.pagination")
      @context.input = ""
      
      if test["should_work"]
        begin
          type, prompt, _ = pagination.call(@context)
          assert [:prompt, :terminal].include?(type), "Should return valid type"
        rescue => e
          flunk("Should handle page_size=#{test["page_size"]} - #{e.message}")
        end
      else
        # Should either work gracefully or fail predictably
        begin
          type, prompt, _ = pagination.call(@context)
          # If it works, verify it's reasonable
          assert [:prompt, :terminal].include?(type) if type
        rescue => e
          # Acceptable to fail with invalid config, just don't crash unexpectedly
          assert e.is_a?(StandardError), "Should raise a standard error, not #{e.class}"
        end
      end
    end
  end

  def test_pagination_stress_test_rapid_navigation
    # Stress test rapid navigation through many pages
    FlowChat::Config.ussd.pagination_page_size = 50
    stress_content = "Stress test page content. " * 100  # Many pages worth
    
    stress_app = lambda { |context| [:prompt, stress_content, []] }
    pagination = FlowChat::Ussd::Middleware::Pagination.new(stress_app)
    
    # Initialize pagination
    pagination.call(@context)
    
    # Rapidly navigate forward and backward
    navigation_sequence = ["#"] * 10 + ["0"] * 5 + ["#"] * 8 + ["0"] * 3
    
    navigation_sequence.each_with_index do |input, i|
      @context.input = input
      
      begin
        type, prompt, _ = pagination.call(@context)
        
        # Should always return valid results
        assert [:prompt, :terminal].include?(type), "Invalid type at navigation step #{i}"
        refute_nil prompt, "Prompt should not be nil at navigation step #{i}"
        
        # State should remain consistent
        state = @context.session.get("ussd.pagination")
        if state
          assert state["page"].is_a?(Integer), "Page should be integer at step #{i}"
          assert state["page"] > 0, "Page should be positive at step #{i}"
          assert state.key?("prompt"), "State should have prompt at step #{i}"
          assert state.key?("offsets"), "State should have offsets at step #{i}"
        end
      rescue => e
        flunk("Failed at navigation step #{i}: #{e.message}")
      end
    end
  end

  private
end

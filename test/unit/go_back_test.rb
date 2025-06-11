require "test_helper"

class GoBackTest < Minitest::Test
  def setup
    @context = FlowChat::Context.new
    @context.session = create_test_session_store
    @context.input = "test_input"
  end

  def test_ussd_app_go_back_deletes_current_screen_and_raises_restart
    app = FlowChat::Ussd::App.new(@context)

    # Add screens to navigation stack
    app.screen(:screen1) { |prompt| "value1" }
    app.screen(:screen2) { |prompt| "value2" }
    
    assert_equal [:screen1, :screen2], app.navigation_stack
    assert_equal "value1", app.session.get(:screen1)
    assert_equal "value2", app.session.get(:screen2)

    # Go back should raise RestartFlow interrupt
    error = assert_raises(FlowChat::Interrupt::RestartFlow) do
      app.go_back
    end

    assert_equal "restart_flow", error.prompt
    
    # Current screen (:screen2) should be deleted
    assert_equal "value1", app.session.get(:screen1)  # Previous screen preserved
    assert_nil app.session.get(:screen2)  # Current screen deleted
  end

  def test_whatsapp_app_go_back_deletes_current_screen_and_raises_restart
    app = FlowChat::Whatsapp::App.new(@context)

    # Add screens to navigation stack
    app.screen(:screen1) { |prompt| "value1" }
    app.screen(:screen2) { |prompt| "value2" }
    
    assert_equal [:screen1, :screen2], app.navigation_stack
    assert_equal "value1", app.session.get(:screen1)
    assert_equal "value2", app.session.get(:screen2)

    # Go back should raise RestartFlow interrupt
    error = assert_raises(FlowChat::Interrupt::RestartFlow) do
      app.go_back
    end

    assert_equal "restart_flow", error.prompt
    
    # Current screen (:screen2) should be deleted
    assert_equal "value1", app.session.get(:screen1)  # Previous screen preserved
    assert_nil app.session.get(:screen2)  # Current screen deleted
  end

  def test_go_back_returns_false_with_empty_navigation_stack
    app = FlowChat::Ussd::App.new(@context)
    assert_empty app.navigation_stack

    # Go back should return false (no restart)
    result = app.go_back
    assert_equal false, result
    assert_empty app.navigation_stack
  end

  def test_go_back_with_single_screen_still_works
    app = FlowChat::Ussd::App.new(@context)

    # Add single screen
    app.screen(:screen1) { |prompt| "value1" }
    assert_equal [:screen1], app.navigation_stack
    assert_equal "value1", app.session.get(:screen1)

    # Go back should work even with single screen
    error = assert_raises(FlowChat::Interrupt::RestartFlow) do
      app.go_back
    end

    assert_equal "restart_flow", error.prompt
    assert_nil app.session.get(:screen1)  # Screen data deleted
  end

  def test_navigation_stack_tracks_screen_order
    app = FlowChat::Ussd::App.new(@context)

    app.screen(:welcome) { |prompt| "welcome_value" }
    assert_equal [:welcome], app.navigation_stack

    app.screen(:menu) { |prompt| "menu_value" }
    assert_equal [:welcome, :menu], app.navigation_stack

    app.screen(:services) { |prompt| "services_value" }
    assert_equal [:welcome, :menu, :services], app.navigation_stack

    # All session data should be stored
    assert_equal "welcome_value", app.session.get(:welcome)
    assert_equal "menu_value", app.session.get(:menu)
    assert_equal "services_value", app.session.get(:services)
  end

  def test_go_back_deletes_last_screen_data_only
    app = FlowChat::Ussd::App.new(@context)

    app.screen(:screen1) { |prompt| "value1" }
    app.screen(:screen2) { |prompt| "value2" }
    app.screen(:screen3) { |prompt| "value3" }

    assert_equal [:screen1, :screen2, :screen3], app.navigation_stack

    # Go back from screen3
    assert_raises(FlowChat::Interrupt::RestartFlow) do
      app.go_back
    end

    # Only screen3 data should be deleted
    assert_equal "value1", app.session.get(:screen1)
    assert_equal "value2", app.session.get(:screen2)
    assert_nil app.session.get(:screen3)  # Deleted
  end

  def test_multiple_go_backs_in_sequence
    app = FlowChat::Ussd::App.new(@context)

    app.screen(:screen1) { |prompt| "value1" }
    app.screen(:screen2) { |prompt| "value2" }
    app.screen(:screen3) { |prompt| "value3" }

    # First go_back (from screen3)
    assert_raises(FlowChat::Interrupt::RestartFlow) { app.go_back }
    assert_nil app.session.get(:screen3)
    assert_equal "value2", app.session.get(:screen2)

    # Create new app instance (simulating restart)
    app2 = FlowChat::Ussd::App.new(@context)
    app2.screen(:screen1) { |prompt| "value1" }  # Should return cached value
    app2.screen(:screen2) { |prompt| "value2" }  # Should return cached value

    # Second go_back (from screen2)  
    assert_raises(FlowChat::Interrupt::RestartFlow) { app2.go_back }
    assert_nil app2.session.get(:screen2)
    assert_equal "value1", app2.session.get(:screen1)
  end

  def test_restart_flow_interrupt_class
    interrupt = FlowChat::Interrupt::RestartFlow.new
    assert_equal "restart_flow", interrupt.prompt
    assert_kind_of FlowChat::Interrupt::Base, interrupt
    assert_kind_of Exception, interrupt
  end

  def test_screen_returns_cached_data_after_go_back_simulation
    app = FlowChat::Ussd::App.new(@context)

    # First execution - store data
    result1 = app.screen(:test_screen) { |prompt| "original_value" }
    assert_equal "original_value", result1
    assert_equal "original_value", app.session.get(:test_screen)

    # Simulate go_back by deleting session data
    app.session.delete(:test_screen)

    # Second execution - should re-prompt (no cached data)
    app2 = FlowChat::Ussd::App.new(@context)
    result2 = app2.screen(:test_screen) { |prompt| "new_value" }
    assert_equal "new_value", result2
    assert_equal "new_value", app2.session.get(:test_screen)
  end

  def test_whatsapp_app_navigation_with_startup_logic
    # Test that WhatsApp's special startup logic doesn't interfere with navigation
    app = FlowChat::Whatsapp::App.new(@context)

    # First screen should set $started_at$
    refute app.session.get("$started_at$")
    app.screen(:welcome) { |prompt| "welcome" }
    assert app.session.get("$started_at$")

    # Add another screen
    app.screen(:menu) { |prompt| "menu_choice" }

    # Go back should work normally
    error = assert_raises(FlowChat::Interrupt::RestartFlow) do
      app.go_back
    end

    assert_equal "restart_flow", error.prompt
    assert_nil app.session.get(:menu)  # Current screen deleted
    assert_equal "welcome", app.session.get(:welcome)  # Previous preserved
    assert app.session.get("$started_at$")  # Startup flag preserved
  end

  def test_navigation_stack_duplicate_prevention_still_works
    app = FlowChat::Ussd::App.new(@context)

    app.screen(:duplicate_test) { |prompt| "first_value" }
    assert_equal [:duplicate_test], app.navigation_stack

    # Attempting to add same screen should raise error
    assert_raises(ArgumentError, "screen has already been presented") do
      app.screen(:duplicate_test) { |prompt| "second_value" }
    end

    # Navigation stack should be unchanged
    assert_equal [:duplicate_test], app.navigation_stack
    assert_equal "first_value", app.session.get(:duplicate_test)
  end

  def test_go_back_practical_flow_simulation
    # Simulate a realistic flow with navigation
    
    # Step 1: Main menu (first time, with input)
    @context.input = "Services"
    app = FlowChat::Ussd::App.new(@context)
    main_choice = app.screen(:main_menu) { |prompt| prompt.user_input }
    assert_equal "Services", main_choice

    # Step 2: Services menu (with fresh input)
    @context.input = "Back"  # Set input for services menu
    app.instance_variable_set(:@input, @context.input)  # Restore input since it was cleared
    services_choice = app.screen(:services_menu) { |prompt| prompt.user_input }
    assert_equal "Back", services_choice

    # Step 3: User chooses to go back
    assert_raises(FlowChat::Interrupt::RestartFlow) do
      app.go_back  # Delete :services_menu data
    end

    # Step 4: Flow restarts - simulate new request
    app2 = FlowChat::Ussd::App.new(@context)
    
    # Main menu has cached data, returns immediately
    main_choice2 = app2.screen(:main_menu) { |prompt| "should_not_execute" }
    assert_equal "Services", main_choice2  # Returns cached value
    
    # Services menu has no cached data (deleted), should re-prompt
    # This is where the user would be prompted again in real flow
    assert_nil app2.session.get(:services_menu)

    # Main menu has cached data, returns immediately
    services_menu_choice2 = app2.screen(:services_menu) { |prompt| "New Response" }
    assert_equal "New Response", services_menu_choice2  # Returns cached value
  end
end 
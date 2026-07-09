# Tests USSD pagination middleware instrumentation
require "test_helper"

module FlowChat
  module Ussd
    module Instrumentation
      class PaginationTest < Minitest::Test
        def setup
          @original_notifications = ActiveSupport::Notifications.notifier
          @test_events = []

          # Create a test notifier that captures events
          @test_notifier = ActiveSupport::Notifications::Fanout.new
          @test_notifier.subscribe(/flow_chat$/) do |name, start, finish, id, payload|
            @test_events << {
              name: name,
              start: start,
              finish: finish,
              id: id,
              payload: payload,
              duration: (finish - start) * 1000
            }
          end

          ActiveSupport::Notifications.instance_variable_set(:@notifier, @test_notifier)

          @context = FlowChat::Context.new
          @context["request.msisdn"] = "+256700123456"
          @context["request.id"] = "test_session_123"
          @context["session.id"] = "ussd:test_session_123"
          @context.session = create_test_session_store
        end

        def teardown
          ActiveSupport::Notifications.instance_variable_set(:@notifier, @original_notifications)
          @test_events.clear
        end

        def test_pagination_middleware_triggers_initial_pagination_event
          # Setup context for initial page - need long content to trigger pagination
          @context["request.input"] = ""

          # Create pagination middleware with app that returns long content
          app = ->(ctx) {
            # Return content that exceeds page size (140 chars)
            long_content = "Please select an option from the menu below:\n\n" \
              "1. Check account balance and transaction history\n" \
              "2. Transfer money to another account\n" \
              "3. Pay bills and utilities\n" \
              "4. Buy airtime and data bundles\n" \
              "5. View and manage savings accounts\n" \
              "6. Apply for loans and credit\n" \
              "7. Update profile information\n" \
              "8. Contact customer support"

            [:prompt, long_content, [], nil]
          }
          pagination = FlowChat::Ussd::Middleware::Pagination.new(app)

          # Call middleware
          # Set controller in context
          controller = Object.new
          def controller.params
            {}
          end
          @context["controller"] = controller

          pagination.call(@context)

          # Find pagination event
          pagination_event = @test_events.find { |e| e[:name] == "pagination.triggered.flow_chat" }

          # Debug: print all events
          if pagination_event.nil?
            puts "\nCaptured events:"
            @test_events.each do |e|
              puts "  Event: #{e[:name]}"
            end
          end

          assert pagination_event, "Should have triggered pagination event"
          assert_equal 1, pagination_event[:payload][:current_page]
          assert pagination_event[:payload][:total_pages] >= 2, "Should have multiple pages"
          assert_equal "initial", pagination_event[:payload][:navigation_action]
        end

        def test_pagination_middleware_triggers_navigation_events
          # Setup context for "More" navigation with proper pagination state
          @context["request.input"] = "#"  # Default pagination next option

          # Set up pagination state from a previous paginated response
          long_content = "Please select an option from the menu below:\n\n" \
            "1. Check account balance and transaction history\n" \
            "2. Transfer money to another account\n" \
            "3. Pay bills and utilities\n" \
            "4. Buy airtime and data bundles\n" \
            "5. View and manage savings accounts\n" \
            "6. Apply for loans and credit\n" \
            "7. Update profile information\n" \
            "8. Contact customer support"

          @context.session.set("ussd.pagination", {
            "page" => 1,
            "total_pages" => 3,
            "active" => true,
            "type" => "prompt",
            "prompt" => long_content,
            "offsets" => {
              "1" => {"start" => 0, "finish" => 100}
            }
          })

          # Create pagination middleware - app won't be called when intercepting
          app = ->(ctx) {
            raise "App should not be called when intercepting pagination"
          }
          pagination = FlowChat::Ussd::Middleware::Pagination.new(app)

          # Call middleware
          # Set controller in context
          controller = Object.new
          def controller.params
            {}
          end
          @context["controller"] = controller

          pagination.call(@context)

          # Find navigation event
          nav_event = @test_events.find { |e|
            e[:name] == "pagination.triggered.flow_chat" && e[:payload][:navigation_action] == "next"
          }

          assert nav_event, "Should have triggered navigation event"
          assert_equal 2, nav_event[:payload][:current_page]
          assert_equal "next", nav_event[:payload][:navigation_action]
        end

        def test_pagination_back_navigation_event
          # Setup context for "Back" navigation
          @context["request.input"] = "0"  # Default pagination back option

          # Set up pagination state from page 2
          long_content = "Please select an option from the menu below:\n\n" \
            "1. Check account balance and transaction history\n" \
            "2. Transfer money to another account\n" \
            "3. Pay bills and utilities\n" \
            "4. Buy airtime and data bundles\n" \
            "5. View and manage savings accounts\n" \
            "6. Apply for loans and credit\n" \
            "7. Update profile information\n" \
            "8. Contact customer support"

          @context.session.set("ussd.pagination", {
            "page" => 2,
            "total_pages" => 3,
            "active" => true,
            "type" => "prompt",
            "prompt" => long_content,
            "offsets" => {
              "1" => {"start" => 0, "finish" => 100},
              "2" => {"start" => 101, "finish" => 200}
            }
          })

          # Create pagination middleware - app won't be called when intercepting
          app = ->(ctx) {
            raise "App should not be called when intercepting pagination"
          }
          pagination = FlowChat::Ussd::Middleware::Pagination.new(app)

          # Call middleware
          # Set controller in context
          controller = Object.new
          def controller.params
            {}
          end
          @context["controller"] = controller

          pagination.call(@context)

          # Find back navigation event
          back_event = @test_events.find { |e|
            e[:name] == "pagination.triggered.flow_chat" && e[:payload][:navigation_action] == "back"
          }

          assert back_event, "Should have triggered back navigation event"
          assert_equal 1, back_event[:payload][:current_page]
          assert_equal "back", back_event[:payload][:navigation_action]
        end

        def test_pagination_terminal_to_prompt_transition_instrumentation
          # Setup for selection from paginated menu
          @context["request.input"] = "1"  # User selects option 1

          # Set up pagination state - user is on a paginated menu
          long_content = "Please select an option from the menu below:\n\n" \
            "1. Check account balance and transaction history\n" \
            "2. Transfer money to another account\n" \
            "3. Pay bills and utilities\n" \
            "4. Buy airtime and data bundles\n" \
            "5. View and manage savings accounts\n" \
            "6. Apply for loans and credit\n" \
            "7. Update profile information\n" \
            "8. Contact customer support"

          @context.session.set("ussd.pagination", {
            "page" => 1,
            "total_pages" => 2,
            "active" => true,
            "type" => "prompt",
            "prompt" => long_content,
            "offsets" => {
              "1" => {"start" => 0, "finish" => 100}
            }
          })

          # App that returns terminal response - this should clear pagination
          app = ->(ctx) {
            [:terminal, "Thank you for selecting account balance. Your balance is $100", [], nil]
          }
          pagination = FlowChat::Ussd::Middleware::Pagination.new(app)

          # Call middleware
          # Set controller in context
          controller = Object.new
          def controller.params
            {}
          end
          @context["controller"] = controller

          result = pagination.call(@context)

          # When user makes a selection, pagination state should be cleared
          # and no pagination event should be triggered
          pagination_events = @test_events.select { |e|
            e[:name] == "pagination.triggered.flow_chat"
          }

          assert_equal 0, pagination_events.length, "Should not trigger pagination events when user makes a selection"
          assert_equal :terminal, result[0], "Should return terminal response"
          assert_nil @context.session.get("ussd.pagination"), "Should clear pagination state"
        end

        def test_pagination_last_page_terminal_navigation_instrumentation
          # Setup for navigating to last page
          @context["request.input"] = "#"  # Next page

          # Set up pagination state - user is on page 2 of 3
          long_content = "Please select an option from the menu below:\n\n" \
            "1. Check account balance and transaction history\n" \
            "2. Transfer money to another account\n" \
            "3. Pay bills and utilities\n" \
            "4. Buy airtime and data bundles\n" \
            "5. View and manage savings accounts\n" \
            "6. Apply for loans and credit\n" \
            "7. Update profile information\n" \
            "8. Contact customer support\n" \
            "9. View recent transactions\n" \
            "10. Change PIN"

          @context.session.set("ussd.pagination", {
            "page" => 2,
            "total_pages" => 3,
            "active" => true,
            "type" => "prompt",
            "prompt" => long_content,
            "offsets" => {
              "1" => {"start" => 0, "finish" => 100},
              "2" => {"start" => 101, "finish" => 200}
            }
          })

          # App won't be called when intercepting
          app = ->(ctx) {
            raise "App should not be called when intercepting pagination"
          }
          pagination = FlowChat::Ussd::Middleware::Pagination.new(app)

          # Call middleware
          # Set controller in context
          controller = Object.new
          def controller.params
            {}
          end
          @context["controller"] = controller

          pagination.call(@context)

          # Find event
          event = @test_events.find { |e| e[:name] == "pagination.triggered.flow_chat" }

          assert event, "Should trigger pagination event for last page"
          assert_equal 3, event[:payload][:current_page]
          assert_equal 3, event[:payload][:total_pages]
          assert_equal "next", event[:payload][:navigation_action]
        end

        def test_pagination_error_boundary_instrumentation
          # Test invalid input handling - user enters invalid choice on paginated menu
          @context["request.input"] = "999"  # Invalid choice (not a menu option or pagination control)

          # Set up pagination state
          long_content = "Please select an option from the menu below:\n\n" \
            "1. Check account balance\n" \
            "2. Transfer money\n" \
            "3. Pay bills\n" \
            "4. Buy airtime"

          @context.session.set("ussd.pagination", {
            "page" => 1,
            "total_pages" => 2,
            "active" => true,
            "type" => "prompt",
            "prompt" => long_content,
            "offsets" => {
              "1" => {"start" => 0, "finish" => 80}
            }
          })

          # App should be called since input is not a pagination control
          app = ->(ctx) {
            # Return error message for invalid input
            [:prompt, "Invalid choice. Please select a valid option from the menu.", [], nil]
          }
          pagination = FlowChat::Ussd::Middleware::Pagination.new(app)

          # Call middleware
          # Set controller in context
          controller = Object.new
          def controller.params
            {}
          end
          @context["controller"] = controller

          result = pagination.call(@context)

          # When user makes invalid selection, pagination state should be cleared
          # and no pagination event should be triggered
          pagination_events = @test_events.select { |e|
            e[:name] == "pagination.triggered.flow_chat"
          }

          assert_equal 0, pagination_events.length, "Should not trigger pagination events for invalid input"
          assert_equal :prompt, result[0], "Should return prompt for error"
          assert_nil @context.session.get("ussd.pagination"), "Should clear pagination state on error"
        end

        def test_pagination_with_media_and_choices_instrumentation
          # Setup context for initial request that will trigger pagination
          @context["request.input"] = ""

          # App returns long content with media that needs pagination
          app = ->(ctx) {
            long_content = "Welcome! Here are your options:\n\n" \
              "1. Check account balance and recent transactions\n" \
              "2. Transfer money to friends and family\n" \
              "3. Pay utility bills and services\n" \
              "4. Buy airtime and data bundles\n" \
              "5. View and manage your savings\n" \
              "6. Apply for loans and credit facilities"

            # Return with media
            [:prompt, long_content, [], {type: :image, url: "http://example.com/menu.jpg"}]
          }
          pagination = FlowChat::Ussd::Middleware::Pagination.new(app)

          # Call middleware
          # Set controller in context
          controller = Object.new
          def controller.params
            {}
          end
          @context["controller"] = controller

          pagination.call(@context)

          # Find pagination event
          event = @test_events.find { |e| e[:name] == "pagination.triggered.flow_chat" }

          assert event, "Should trigger pagination event"
          assert_equal "initial", event[:payload][:navigation_action]
          assert_equal 1, event[:payload][:current_page]
          # Note: The current pagination implementation doesn't track media in the instrumentation payload
          # This would need to be added to the middleware if required
        end

        private

        def create_test_session_store
          store = Object.new

          def store.data
            @data ||= {}
          end

          def store.get(key)
            data[key]
          end

          def store.set(key, value)
            data[key] = value
          end

          def store.delete(key)
            data.delete(key)
          end

          store
        end
      end
    end
  end
end

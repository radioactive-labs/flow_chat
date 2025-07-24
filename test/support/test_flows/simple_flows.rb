module FlowChat
  module TestSupport
    module TestFlows
      # Test flow classes for basic functionality
      class HelloWorldFlow < FlowChat::Flow
        def main_page
          app.say "Hello World!"
        end
      end

      class NameCollectionFlow < FlowChat::Flow
        def main_page
          name = app.screen(:name) { |prompt| prompt.ask "What is your name?" }
          app.say "Hello, #{name}!"
        end
      end

      class MultiStepFlow < FlowChat::Flow
        def main_page
          name = app.screen(:name) { |prompt|
            prompt.ask "What is your name?", transform: ->(input) { input.strip.titleize }
          }

          age = app.screen(:age) do |prompt|
            prompt.ask "How old are you?",
              validate: ->(input) { "You must be at least 13 years old" unless input.to_i >= 13 },
              transform: ->(input) { input.to_i }
          end

          gender = app.screen(:gender) { |prompt| prompt.select "What is your gender?", ["Male", "Female"] }

          confirm = app.screen(:confirm) do |prompt|
            prompt.yes?("Is this correct?\n\nName: #{name}\nAge: #{age}\nGender: #{gender}")
          end

          app.say confirm ? "Thank you for confirming" : "Please try again"
        end
      end
    end
  end
end

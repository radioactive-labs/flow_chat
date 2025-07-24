module FlowChat
  module TestSupport
    module TestFlows
      # Simple test flow that focuses on choice selection
      class ChoiceTestFlow < FlowChat::Flow
        def main_page
          # Test select with array choices
          satisfaction = app.screen(:satisfaction) do |prompt|
            prompt.select "Rate our service:", ["Poor", "Good", "Excellent"]
          end

          # Test yes/no question
          recommend = app.screen(:recommend) do |prompt|
            prompt.yes? "Would you recommend us?"
          end

          # Return the collected data
          app.say "Thanks! Rating: #{satisfaction}, Recommend: #{recommend}"
        end
      end
    end
  end
end

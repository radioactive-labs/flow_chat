module FlowChat
  module TestSupport
    module TestFlows
      # Test flow for WhatsApp integration testing
      class TestWhatsappFlow < FlowChat::Flow
        def main_page
          name = app.screen(:name) do |prompt|
            if app.input && !app.input.empty?
              prompt.ask "Hello #{app.input}! What can I help you with?",
                transform: ->(input) { input.strip.downcase }
            else
              prompt.ask "Welcome! What's your name?",
                transform: ->(input) { input.strip.titleize }
            end
          end

          app.say "Thanks #{name}! Your request has been processed."
        end
      end
    end
  end
end

module UssdEngine
  module Controller
    module Io
      protected

      def basic_prompt(message)
        Config.logger&.debug "UssdEngine::Controller::Io :: Sending prompt -> \n\n#{message}\n"
        {
          body: message,
          type: :prompt,
        }
      end

      def terminate(message)
        Config.logger&.debug "UssdEngine::Controller::Io :: Terminating session -> \n\n#{message}\n"
        {
          body: message,
          type: :terminal,
        }
      end
    end
  end
end

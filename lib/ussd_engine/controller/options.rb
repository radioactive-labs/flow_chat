module UssdEngine
  module Controller
    module Options
      protected

      def options_prompt(message, options)
        message += build_options_nav(options)
        Config.logger&.debug "UssdEngine::Controller::Options :: Sending prompt -> \n\n#{message}\n"
        {
          body: message,
          type: :prompt,
        }
      end

      def build_options_nav(options)
        "\n\n" + options.each_with_index.map { |x, i| "#{i + 1} #{x[1]}" }.join("\n")
      end

      def resolve_option(input, options)
        return unless input.to_s.match? /^[1-9](\d)?$/

        options.keys[input.to_i - 1]
      end

      def back_option
        { back: "Back" }
      end

      def cancel_option
        { cancel: "Cancel" }
      end
    end
  end
end

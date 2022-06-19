module UssdEngine
  module Controller
    def self.included(base)
      base.send :skip_before_action, :verify_authenticity_token, only: %i[ussd_controller]
    end

    def ussd_controller
      unless request.env["ussd_engine.request"].present?
        Config.logger&.warning "UssdEngine::Controller :: Unknown request type"
        return render(status: :bad_request)
      end

      if request.env["ussd_engine.request"][:type] == :initial
        Config.logger&.info "UssdEngine::Controller :: Starting new session"
        current_screen = :index
      else
        Config.logger&.info "UssdEngine::Controller :: Continuing existing session"
        user_input = request.env["ussd_engine.request"][:input]
        current_screen = session["ussd_engine.screen"] || :index
      end
      # For testing purposes
      user_input = request.env["ussd_engine.request"][:input]

      display current_screen, user_input

      render body: nil
    end

    protected

    def display(screen, input = nil)
      Config.logger&.info "UssdEngine::Controller :: Displaying #{screen}"
      session["ussd_engine.screen"] = screen
      request.env["ussd_engine.response"] = send screen.to_sym, input
    end

    def prompt(message, options = nil)
      Config.logger&.info "UssdEngine::Controller :: Sending prompt -> #{message}"
      message += build_options_nav(options) unless options.blank?
      {
        body: message,
        type: :prompt,
      }
    end

    def terminate(message)
      Config.logger&.info "UssdEngine::Controller :: Terminating session -> #{message}"
      session.delete "ussd_engine.screen"
      {
        body: message,
        type: :terminate,
      }
    end

    def build_options_nav(options)
      "\n\n" + options.each_with_index.map { |x, i| "#{i + 1} #{x[1]}" }.join("\n")
    end

    def resolve_option(input, options)
      return unless input.match? /^[1-9](\d)?$/

      options.keys[input.to_i - 1]
    end
  end
end

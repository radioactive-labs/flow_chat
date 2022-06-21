module UssdEngine
  module Controller
    def self.included(base)
      base.send :skip_before_action, :verify_authenticity_token, only: :ussd_controller, raise: false
    end

    def ussd_controller
      unless request.env["ussd_engine.request"].present?
        Config.logger&.warn "UssdEngine::Controller :: Unknown request type"
        return render(status: :bad_request)
      end

      initial_screen, user_input = resolve_initial_screen
      display initial_screen, user_input

      render body: nil
    end

    protected

    def display(screen, input = nil)
      Config.logger&.debug "UssdEngine::Controller :: Displaying #{screen}"
      session["ussd_engine.screen"] = screen
      request.env["ussd_engine.response"] = send screen.to_sym, input
    end

    def prompt(message, options = nil)
      message += build_options_nav(options) unless options.blank?
      Config.logger&.debug "UssdEngine::Controller :: Sending prompt -> \n\n#{message}\n"
      {
        body: message,
        type: :prompt,
      }
    end

    def terminate(message)
      Config.logger&.debug "UssdEngine::Controller :: Terminating session -> \n\n#{message}\n"
      {
        body: message,
        type: :terminal,
      }
    end

    def build_options_nav(options)
      "\n\n" + options.each_with_index.map { |x, i| "#{i + 1} #{x[1]}" }.join("\n")
    end

    def resolve_option(input, options)
      return unless input.match? /^[1-9](\d)?$/

      options.keys[input.to_i - 1]
    end

    def ussd_request_id
      request.env["ussd_engine.request"][:id]
    end

    def ussd_request_type
      request.env["ussd_engine.request"][:type]
    end

    def ussd_request_msisdn
      request.env["ussd_engine.request"][:msisdn]
    end

    def ussd_request_provider
      request.env["ussd_engine.request"][:provider]
    end

    def ussd_user_input
      request.env["ussd_engine.request"][:input]
    end

    def resolve_initial_screen
      if ussd_request_type == :initial
        Config.logger&.debug "UssdEngine::Controller :: Starting new session"
        reset_session
        initial_screen = :index
      else
        Config.logger&.debug "UssdEngine::Controller :: Continuing existing session"
        user_input = ussd_user_input
        initial_screen = session["ussd_engine.screen"] || :index
      end

      [initial_screen, user_input]
    end
  end
end

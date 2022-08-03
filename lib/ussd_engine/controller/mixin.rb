require "ussd_engine/controller/io"
require "ussd_engine/controller/options"
require "ussd_engine/controller/params"
require "ussd_engine/controller/storable"
require "ussd_engine/controller/forkable"

module UssdEngine
  module Controller
    module Mixin
      include UssdEngine::Controller::Io
      include UssdEngine::Controller::Options
      include UssdEngine::Controller::Params

      def self.included(base)
        base.send :include, UssdEngine::Controller::Storable
        base.send :include, UssdEngine::Controller::Forkable
        base.send :skip_before_action, :verify_authenticity_token, only: :ussd_controller, raise: false
      end

      def ussd_controller
        unless request.env["ussd_engine.request"].present?
          Config.logger&.warn "UssdEngine::Controller::Mixin :: Unknown request type"
          return render(status: :bad_request)
        end

        process_ussd_request build_ussd_request
        render body: nil
      end

      protected

      def process_ussd_request(ussd_request)
        display(ussd_request[:screen], ussd_request[:input])
      end

      def display(screen, input = nil)
        Config.logger&.debug "UssdEngine::Controller::Mixin :: Display #{screen}"
        session["ussd_engine.screen"] = screen
        request.env["ussd_engine.response"] = send screen.to_sym, input
      end

      def build_ussd_request
        if ussd_request_type == :initial
          Config.logger&.debug "UssdEngine::Controller::Mixin :: Starting new session"
          reset_session
          ussd_screen = :index
        else
          Config.logger&.debug "UssdEngine::Controller::Mixin :: Continuing existing session"
          user_input = ussd_user_input
          ussd_screen = session["ussd_engine.screen"] || :index
        end

        { screen: ussd_screen, input: user_input }
      end

      def prompt(message, options = nil)
        return basic_prompt(message) if options.blank?

        options_prompt(message, options)
      end
    end
  end
end

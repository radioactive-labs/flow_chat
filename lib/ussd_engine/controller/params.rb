require "ussd_engine/controller/io"
require "ussd_engine/controller/options"

module UssdEngine
  module Controller
    module Params
      protected

      def ussd_request_id
        return unless request.env["ussd_engine.request"].present?

        request.env["ussd_engine.request"][:id]
      end

      def ussd_request_type
        return unless request.env["ussd_engine.request"].present?

        request.env["ussd_engine.request"][:type]
      end

      def ussd_request_msisdn
        return unless request.env["ussd_engine.request"].present?

        request.env["ussd_engine.request"][:msisdn]
      end

      def ussd_request_provider
        return unless request.env["ussd_engine.request"].present?

        request.env["ussd_engine.request"][:provider]
      end

      def ussd_user_input
        return unless request.env["ussd_engine.request"].present?

        request.env["ussd_engine.request"][:input]
      end
    end
  end
end

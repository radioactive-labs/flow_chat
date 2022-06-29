require "ussd_engine/controller/io"
require "ussd_engine/controller/options"

module UssdEngine
  module Controller
    module Params
      protected

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
    end
  end
end

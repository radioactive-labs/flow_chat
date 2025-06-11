module FlowChat
  module Whatsapp
    class App < FlowChat::BaseApp
      def contact_name
        context["request.contact_name"]
      end

      def location
        context["request.location"]
      end

      def media
        context["request.media"]
      end

      protected

      # WhatsApp has special startup logic and supports media
      def prepare_user_input
        user_input = input
        if session.get("$started_at$").nil?
          session.set("$started_at$", Time.current.iso8601)
          user_input = nil
        end
        user_input
      end
    end
  end
end

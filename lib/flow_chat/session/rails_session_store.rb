module FlowChat
  module Session
    class RailsSessionStore
      def initialize(context)
        @session_id = context["session.id"]
        @session_store = context.controller.session
        @session_data = (session_store[session_id] || {}).with_indifferent_access
      end

      def get(key)
        session_data[key]
      end

      def set(key, value)
        session_data[key] = value
        session_store[session_id] = session_data
        value
      end

      def delete(key)
        set key, nil
      end

      def destroy
        session_store[session_id] = nil
      end

      private

      attr_reader :session_id, :session_store, :session_data
    end
  end
end

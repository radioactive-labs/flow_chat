module FlowChat
  module Session
    class RailsSessionStore
      include FlowChat::Instrumentation

      # Make context available for instrumentation enrichment
      attr_reader :context

      def initialize(context)
        @context = context
        @session_id = context["session.id"]
        @session_store = context.controller.session
        @session_data = (session_store[session_id] || {}).with_indifferent_access

        FlowChat.logger.debug { "RailsSessionStore: Initialized Rails session store for session #{session_id}" }
        FlowChat.logger.debug { "RailsSessionStore: Loaded session data with #{session_data.keys.size} keys" }
      end

      def get(key)
        value = session_data[key]

        # Use instrumentation for data get
        instrument(Events::SESSION_DATA_GET, {
          session_id: session_id,
          key: key.to_s,
          value: value
        })

        value
      end

      def set(key, value)
        FlowChat.logger.debug { "RailsSessionStore: Setting key '#{key}' = #{value.inspect} in session #{session_id}" }

        session_data[key] = value
        session_store[session_id] = session_data

        # Use instrumentation for data set
        instrument(Events::SESSION_DATA_SET, {
          session_id: session_id,
          key: key.to_s
        })

        FlowChat.logger.debug { "RailsSessionStore: Session data saved to Rails session store" }
        value
      end

      def delete(key)
        FlowChat.logger.debug { "RailsSessionStore: Deleting key '#{key}' from session #{session_id}" }
        set key, nil
      end

      def destroy
        # Use instrumentation for session destruction
        instrument(Events::SESSION_DESTROYED, {
          session_id: session_id,
          gateway: "rails" # Rails doesn't have a specific gateway context
        })

        session_store[session_id] = nil
      end

      private

      attr_reader :session_id, :session_store, :session_data
    end
  end
end

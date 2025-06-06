module FlowChat
  module Session
    class RailsSessionStore
      def initialize(context)
        @session_id = context["session.id"]
        @session_store = context.controller.session
        @session_data = (session_store[session_id] || {}).with_indifferent_access
        
        FlowChat.logger.debug { "RailsSessionStore: Initialized Rails session store for session #{session_id}" }
        FlowChat.logger.debug { "RailsSessionStore: Loaded session data with #{session_data.keys.size} keys" }
      end

      def get(key)
        value = session_data[key]
        FlowChat.logger.debug { "RailsSessionStore: Getting key '#{key}' from session #{session_id} = #{value.inspect}" }
        value
      end

      def set(key, value)
        FlowChat.logger.debug { "RailsSessionStore: Setting key '#{key}' = #{value.inspect} in session #{session_id}" }
        
        session_data[key] = value
        session_store[session_id] = session_data
        
        FlowChat.logger.debug { "RailsSessionStore: Session data saved to Rails session store" }
        value
      end

      def delete(key)
        FlowChat.logger.debug { "RailsSessionStore: Deleting key '#{key}' from session #{session_id}" }
        set key, nil
      end

      def destroy
        FlowChat.logger.info { "RailsSessionStore: Destroying session #{session_id}" }
        session_store[session_id] = nil
      end

      private

      attr_reader :session_id, :session_store, :session_data
    end
  end
end

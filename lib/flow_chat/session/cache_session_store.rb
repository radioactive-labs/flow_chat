module FlowChat
  module Session
    class CacheSessionStore
      include FlowChat::Instrumentation
      
      # Make context available for instrumentation enrichment
      attr_reader :context
      
      def initialize(context, cache = nil)
        @context = context
        @cache = cache || FlowChat::Config.cache

        raise ArgumentError, "Cache is required. Set FlowChat::Config.cache or pass a cache instance." unless @cache
        
        FlowChat.logger.debug { "CacheSessionStore: Initialized cache session store for session #{session_key}" }
        FlowChat.logger.debug { "CacheSessionStore: Cache backend: #{@cache.class.name}" }
      end

      def get(key)
        return nil unless @context

        FlowChat.logger.debug { "CacheSessionStore: Getting key '#{key}' from session #{session_key}" }
        
        data = @cache.read(session_key)
        session_id = @context["session.id"]
        
        unless data
          # Use instrumentation for cache miss
          instrument(Events::SESSION_CACHE_MISS, {
            session_id: session_id,
            key: key.to_s
          })
          return nil
        end

        value = data[key.to_s]
        
        # Use instrumentation for cache hit and data get
        instrument(Events::SESSION_CACHE_HIT, {
          session_id: session_id,
          key: key.to_s
        })
        
        instrument(Events::SESSION_DATA_GET, {
          session_id: session_id,
          key: key.to_s,
          value: value
        })
        
        value
      end

      def set(key, value)
        return unless @context

        FlowChat.logger.debug { "CacheSessionStore: Setting key '#{key}' = #{value.inspect} in session #{session_key}" }

        data = @cache.read(session_key) || {}
        data[key.to_s] = value

        ttl = session_ttl
        @cache.write(session_key, data, expires_in: ttl)
        
        # Use instrumentation for data set
        instrument(Events::SESSION_DATA_SET, {
          session_id: @context["session.id"],
          key: key.to_s
        })
        
        FlowChat.logger.debug { "CacheSessionStore: Session data saved with TTL #{ttl.inspect}" }
        value
      end

      def delete(key)
        return unless @context

        FlowChat.logger.debug { "CacheSessionStore: Deleting key '#{key}' from session #{session_key}" }

        data = @cache.read(session_key)
        unless data
          FlowChat.logger.debug { "CacheSessionStore: No session data found for deletion" }
          return
        end

        data.delete(key.to_s)
        @cache.write(session_key, data, expires_in: session_ttl)
        
        FlowChat.logger.debug { "CacheSessionStore: Key '#{key}' deleted from session" }
      end

      def clear
        return unless @context

        # Use instrumentation for session destruction
        instrument(Events::SESSION_DESTROYED, {
          session_id: @context["session.id"],
        })
        
        @cache.delete(session_key)
      end

      # Alias for compatibility
      alias_method :destroy, :clear

      def exists?
        exists = @cache.exist?(session_key)
        FlowChat.logger.debug { "CacheSessionStore: Session #{session_key} exists: #{exists}" }
        exists
      end

      private

      def session_key
        return "flow_chat:session:nil_context" unless @context

        gateway = @context["request.gateway"]
        msisdn = @context["request.msisdn"]

        key = case gateway
        when :whatsapp_cloud_api
          "flow_chat:session:whatsapp:#{msisdn}"
        when :nalo, :nsano
          session_id = @context["request.id"]
          "flow_chat:session:ussd:#{session_id}:#{msisdn}"
        else
          "flow_chat:session:unknown:#{msisdn}"
        end
        
        FlowChat.logger.debug { "CacheSessionStore: Generated session key: #{key}" }
        key
      end

      def session_ttl
        gateway = @context["request.gateway"]

        ttl = case gateway
        when :whatsapp_cloud_api
          7.days  # WhatsApp conversations can be long-lived
        when :nalo, :nsano
          1.hour  # USSD sessions are typically short
        else
          1.day   # Default
        end
        
        FlowChat.logger.debug { "CacheSessionStore: Session TTL for #{gateway}: #{ttl.inspect}" }
        ttl
      end
    end
  end
end

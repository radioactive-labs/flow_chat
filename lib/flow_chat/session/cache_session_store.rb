module FlowChat
  module Session
    class CacheSessionStore
      def initialize(context, cache = nil)
        @context = context
        @cache = cache || FlowChat::Config.cache

        raise ArgumentError, "Cache is required. Set FlowChat::Config.cache or pass a cache instance." unless @cache
      end

      def get(key)
        return nil unless @context

        data = @cache.read(session_key)
        return nil unless data

        data[key.to_s]
      end

      def set(key, value)
        return unless @context

        data = @cache.read(session_key) || {}
        data[key.to_s] = value

        @cache.write(session_key, data, expires_in: session_ttl)
        value
      end

      def delete(key)
        return unless @context

        data = @cache.read(session_key)
        return unless data

        data.delete(key.to_s)
        @cache.write(session_key, data, expires_in: session_ttl)
      end

      def clear
        return unless @context

        @cache.delete(session_key)
      end

      # Alias for compatibility
      alias_method :destroy, :clear

      def exists?
        @cache.exist?(session_key)
      end

      private

      def session_key
        gateway = @context["request.gateway"]
        msisdn = @context["request.msisdn"]

        case gateway
        when :whatsapp_cloud_api
          "flow_chat:session:whatsapp:#{msisdn}"
        when :nalo, :nsano
          session_id = @context["request.id"]
          "flow_chat:session:ussd:#{session_id}:#{msisdn}"
        else
          "flow_chat:session:unknown:#{msisdn}"
        end
      end

      def session_ttl
        gateway = @context["request.gateway"]

        case gateway
        when :whatsapp_cloud_api
          7.days  # WhatsApp conversations can be long-lived
        when :nalo, :nsano
          1.hour  # USSD sessions are typically short
        else
          1.day   # Default
        end
      end
    end
  end
end

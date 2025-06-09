module FlowChat
  module Session
    class Middleware
      include FlowChat::Instrumentation

      attr_reader :context

      def initialize(app, session_options)
        @app = app
        @session_options = session_options
        FlowChat.logger.debug { "Session::Middleware: Initialized session middleware" }
      end

      def call(context)
        @context = context
        session_id = session_id(context)
        FlowChat.logger.debug { "Session::Middleware: Generated session ID: #{session_id}" }

        context["session.id"] = session_id
        context.session = context["session.store"].new(context)

        # Use instrumentation instead of direct logging for session creation
        store_type = context["session.store"].name || "$Anonymous"
        instrument(Events::SESSION_CREATED, {
          session_id: session_id,
          store_type: store_type,
          gateway: context["request.gateway"]
        })

        FlowChat.logger.debug { "Session::Middleware: Session store: #{context["session.store"].class.name}" }

        result = @app.call(context)

        FlowChat.logger.debug { "Session::Middleware: Session processing completed for #{session_id}" }
        result
      rescue => error
        FlowChat.logger.error { "Session::Middleware: Error in session processing for #{session_id}: #{error.class.name}: #{error.message}" }
        raise
      end

      private

      def session_id(context)
        gateway = context["request.gateway"]
        platform = context["request.platform"]
        flow_name = context["flow.name"]

        # Check for explicit session ID first (for manual session management)
        if context["session.id"].present?
          session_id = context["session.id"]
          FlowChat.logger.debug { "Session::Middleware: Using explicit session ID: #{session_id}" }
          return session_id
        end

        FlowChat.logger.debug { "Session::Middleware: Building session ID for platform=#{platform}, gateway=#{gateway}, flow=#{flow_name}" }

        # Get identifier based on configuration
        identifier = get_session_identifier(context)

        # Build session ID based on configuration
        session_id = build_session_id(flow_name, platform, gateway, identifier)
        FlowChat.logger.debug { "Session::Middleware: Generated session ID: #{session_id}" }
        session_id
      end

      def get_session_identifier(context)
        identifier_type = @session_options.identifier
        
        # If no identifier specified, use platform defaults
        if identifier_type.nil?
          platform = context["request.platform"]
          identifier_type = case platform
          when :ussd
            :request_id    # USSD defaults to ephemeral sessions
          when :whatsapp
            :msisdn       # WhatsApp defaults to durable sessions
          else
            :msisdn       # Default fallback to durable
          end
        end
        
        case identifier_type
        when :request_id
          context["request.id"]
        when :msisdn
          phone = context["request.msisdn"]
          @session_options.hash_phone_numbers ? hash_phone_number(phone) : phone
        else
          raise "Invalid session identifier type: #{identifier_type}"
        end
      end

      def build_session_id(flow_name, platform, gateway, identifier)
        parts = []

        # Add flow name if flow isolation is enabled
        parts << flow_name if @session_options.boundaries.include?(:flow)

        # Add platform if platform isolation is enabled
        parts << platform.to_s if @session_options.boundaries.include?(:platform)

        # Add provider/gateway if provider isolation is enabled
        parts << gateway.to_s if @session_options.boundaries.include?(:provider)

        # Add URL if URL isolation is enabled
        if @session_options.boundaries.include?(:url)
          url_identifier = get_url_identifier(context)
          parts << url_identifier if url_identifier.present?
        end

        # Add the session identifier
        parts << identifier if identifier.present?

        # Join parts with colons
        parts.join(":")
      end

      def get_url_identifier(context)
        request = context.controller&.request
        return nil unless request

        # Extract host and path for URL boundary
        host = request.host rescue nil
        path = request.path rescue nil

        # Create a normalized URL identifier: host + path 
        # e.g., "example.com/api/v1/ussd" or "tenant1.example.com/ussd"
        url_parts = []
        url_parts << host if host.present?
        url_parts << path.sub(/^\//, '') if path.present? && path != '/'

        # For long URLs, use first part + hash suffix instead of full hash
        url_identifier = url_parts.join('/').gsub(/[^a-zA-Z0-9._-]/, '_')
        if url_identifier.length > 50
          require 'digest'
          # Take first 41 chars + hash suffix to keep it manageable but recognizable
          first_part = url_identifier[0, 41]
          hash_suffix = Digest::SHA256.hexdigest(url_identifier)[0, 8]
          url_identifier = "#{first_part}_#{hash_suffix}"
        end

        url_identifier
      end

      def hash_phone_number(phone)
        # Use SHA256 but only take first 8 characters for reasonable session IDs
        require 'digest'
        Digest::SHA256.hexdigest(phone.to_s)[0, 8]
      end
    end
  end
end

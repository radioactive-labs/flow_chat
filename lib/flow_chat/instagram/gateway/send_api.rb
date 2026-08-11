module FlowChat
  module Instagram
    module Gateway
      # Instagram DMs, on the shared Messenger Platform envelope.
      #
      # A sibling of the Messenger gateway rather than a subclass of it: the
      # two differ in credentials, limits and subscription object, and
      # neither owns the other.
      class SendApi < FlowChat::Meta::MessagingGateway
        def platform
          :instagram
        end

        def gateway_name
          :instagram_send_api
        end

        def configuration_class
          FlowChat::Instagram::Configuration
        end

        def client_class
          FlowChat::Instagram::Client
        end

        def renderer_class
          FlowChat::Instagram::Renderer
        end

        def self.choice_mapper_class
          FlowChat::Instagram::Middleware::ChoiceMapper
        end

        # Confirm against the Meta app dashboard before relying on this. On
        # the Facebook Login path Meta's own docs were ambiguous about
        # whether these arrive under "page" or "instagram", which is why
        # this is a hook rather than a hard-coded assumption.
        FACEBOOK_LOGIN_WEBHOOK_OBJECT = "instagram"

        # Confirm against the Meta app dashboard before relying on this, same
        # as FACEBOOK_LOGIN_WEBHOOK_OBJECT above. Kept as its own constant
        # rather than sharing one: the two integration paths are configured
        # independently in Meta's dashboard, so a correction to one path's
        # value must not silently change the other's.
        INSTAGRAM_LOGIN_WEBHOOK_OBJECT = "instagram"

        def expected_webhook_object
          (@config.login == :instagram) ? INSTAGRAM_LOGIN_WEBHOOK_OBJECT : FACEBOOK_LOGIN_WEBHOOK_OBJECT
        end

        private

        def configuration_error_class
          FlowChat::Instagram::ConfigurationError
        end

        def platform_label
          "Instagram"
        end
      end
    end
  end
end

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

        # Confirmed against a live delivery for a page-linked account: Meta's
        # docs are ambiguous about whether these arrive under "page" or
        # "instagram", and they arrive under "instagram". The delivery named
        # the Instagram professional account in entry.id, not the linked Page,
        # which is what webhook_account_id encodes.
        FACEBOOK_LOGIN_WEBHOOK_OBJECT = "instagram"

        # Kept as its own constant rather than sharing one with the path above:
        # the two integrations are configured independently in Meta's
        # dashboard, so a correction to one path's value must not silently
        # change the other's.
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

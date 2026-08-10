module FlowChat
  module Meta
    # The GET handshake Meta performs when a webhook URL is registered.
    #
    # The including gateway must have @config responding to #verify_token,
    # @controller, and must include FlowChat::Meta::GatewayIdentity (directly or
    # via another Meta:: behavior module) to supply #platform.
    module WebhookVerification
      include FlowChat::Meta::GatewayIdentity

      private

      def handle_verification(context)
        params = @controller.request.params

        verify_token = @config.verify_token
        provided_token = params["hub.verify_token"]
        challenge = params["hub.challenge"]

        # A configuration with no verify token must not verify anything. Without
        # the presence check a missing token on both sides compares equal, and
        # anyone could claim the endpoint by asking for the challenge.
        verified = verify_token.present? && FlowChat::Security.secure_compare(provided_token.to_s, verify_token)

        FlowChat.logger.debug { "#{log_tag}: Webhook verification - provided token matches: #{verified}" }

        if verified
          instrument(FlowChat::Instrumentation::Events::WEBHOOK_VERIFIED, {
            challenge: challenge,
            platform: platform
          })

          @controller.render plain: challenge
        else
          instrument(FlowChat::Instrumentation::Events::WEBHOOK_FAILED, {
            reason: "Invalid verify token",
            platform: platform
          })

          @controller.head :forbidden
        end
      end
    end
  end
end

module FlowChat
  module Meta
    # The GET handshake Meta performs when a webhook URL is registered.
    #
    # The including gateway must have @config responding to #verify_token,
    # @controller, and must include FlowChat::Meta::GatewayIdentity (directly or
    # via another Meta:: behavior module) to supply #platform.
    #
    # What it adds over FlowChat::Meta::Challenge is the gateway's share:
    # instrumenting the outcome and answering through the controller. An
    # application holding Meta's webhooks outside a gateway wants Challenge.
    module WebhookVerification
      include FlowChat::Meta::GatewayIdentity

      private

      def handle_verification(context)
        params = @controller.request.params

        challenge = FlowChat::Meta::Challenge.answer(params, @config.verify_token)
        verified = !challenge.nil?

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

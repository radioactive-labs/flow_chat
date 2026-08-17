require "openssl"

module FlowChat
  module Meta
    # X-Hub-Signature-256 validation, shared by every Meta webhook gateway.
    #
    # The including gateway must have @config responding to #app_secret and
    # #skip_signature_validation, and must include FlowChat::Meta::GatewayIdentity
    # (directly or via another Meta:: behavior module) to supply platform_label
    # and configuration_error_class.
    #
    # What it adds over FlowChat::Meta::Signature is the gateway's share: the
    # opt out, treating a missing secret as the developer's mistake rather than
    # an answer, reading the body off a Rack request, and the logging. An
    # application holding Meta's webhooks outside a gateway wants Signature.
    module SignatureValidation
      include FlowChat::Meta::GatewayIdentity

      private

      def valid_webhook_signature?(request)
        if @config.skip_signature_validation
          FlowChat.logger.debug { "#{log_tag}: Webhook signature validation is disabled" }
          return true
        end

        # Deliberately wider than a nil-or-empty check: a whitespace-only secret is
        # never intentional, and computing an HMAC with it would silently accept
        # traffic under a "secret" that offers no protection.
        if @config.app_secret.blank?
          error_msg = "#{platform_label} app_secret is required for webhook signature validation. " \
            "Either configure app_secret or set skip_signature_validation=true to explicitly disable validation."
          FlowChat.logger.error { "#{log_tag}: #{error_msg}" }
          raise configuration_error_class, error_msg
        end

        signature_header = request.headers[FlowChat::Meta::Signature::HEADER]
        unless signature_header
          FlowChat.logger.warn { "#{log_tag}: No #{FlowChat::Meta::Signature::HEADER} header found in request" }
          return false
        end

        request.body.rewind
        body = request.body.read
        request.body.rewind

        signature_valid = FlowChat::Meta::Signature.valid?(body, signature_header, @config.app_secret)

        if signature_valid
          FlowChat.logger.debug { "#{log_tag}: Webhook signature validation successful" }
        else
          FlowChat.logger.warn { "#{log_tag}: Webhook signature validation failed - signatures do not match" }
        end

        signature_valid
      rescue => e
        # A misconfiguration is the developer's problem and must not be swallowed
        # into a plain "invalid signature".
        raise if e.is_a?(configuration_error_class)

        FlowChat.logger.error { "#{log_tag}: Error validating webhook signature: #{e.class.name}: #{e.message}" }
        false
      end
    end
  end
end

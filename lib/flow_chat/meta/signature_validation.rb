require "openssl"

module FlowChat
  module Meta
    # X-Hub-Signature-256 validation, shared by every Meta webhook gateway.
    #
    # The including gateway must have @config responding to #app_secret and
    # #skip_signature_validation. It may override platform_label, log_tag and
    # configuration_error_class.
    module SignatureValidation
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

        signature_header = request.headers["X-Hub-Signature-256"]
        unless signature_header
          FlowChat.logger.warn { "#{log_tag}: No X-Hub-Signature-256 header found in request" }
          return false
        end

        expected_signature = signature_header.sub("sha256=", "")

        request.body.rewind
        body = request.body.read
        request.body.rewind

        calculated_signature = OpenSSL::HMAC.hexdigest(
          OpenSSL::Digest.new("sha256"),
          @config.app_secret,
          body
        )

        signature_valid = FlowChat::Security.secure_compare(expected_signature, calculated_signature)

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

      private

      def configuration_error_class
        FlowChat::Meta::ConfigurationError
      end

      def platform_label
        "Meta"
      end

      def log_tag
        self.class.name.split("::").last
      end
    end
  end
end

require "openssl"

module FlowChat
  module Meta
    # Whether a body carries Meta's signature for a given secret.
    #
    # The decision on its own, with no configuration, logging or gateway around
    # it. Meta signs every product's webhook the same way, and an application
    # that receives one outside a gateway needs this answer without the rest:
    # a single endpoint serving several tenants has to verify the delivery
    # before it can know whose it is, which is before it has a gateway to ask.
    #
    # SignatureValidation is the gateway's way in, and calls this.
    module Signature
      HEADER = "X-Hub-Signature-256"

      # Total, rather than raising on a missing secret. A caller with no secret
      # configured is not asking a different question; it is asking this one and
      # the answer is no. A gateway that would rather treat that as the
      # developer's mistake checks for it before asking.
      def self.valid?(body, header, secret)
        return false if secret.to_s.strip.empty? || header.to_s.empty?

        expected = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), secret, body.to_s)

        FlowChat::Security.secure_compare(header.to_s.delete_prefix("sha256="), expected)
      end
    end
  end
end

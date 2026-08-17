module FlowChat
  module Meta
    # The GET handshake Meta performs when a webhook URL is registered, as a
    # decision rather than a response.
    #
    # Returns the challenge to echo, or nil when the request has not proved it
    # is Meta. What to do with either answer belongs to the caller: a gateway
    # renders it through its controller, an application receiving Meta's
    # webhooks outside a gateway renders it its own way.
    #
    # WebhookVerification is the gateway's way in, and calls this.
    module Challenge
      # A configuration with no verify token must not verify anything. Without
      # the presence check a missing token on both sides compares equal, and
      # anyone could claim the endpoint by asking for the challenge.
      def self.answer(params, verify_token)
        return nil if verify_token.to_s.strip.empty?
        return nil unless FlowChat::Security.secure_compare(params["hub.verify_token"].to_s, verify_token)

        params["hub.challenge"]
      end
    end
  end
end

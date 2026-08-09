require "openssl"
require "active_support/security_utils"

module FlowChat
  # Shared security helpers: constant-time comparison for webhook secrets and
  # signatures, and the signed cookie that authorizes simulator mode.
  module Security
    SIMULATOR_COOKIE_NAME = "flowchat_simulator"

    # How long a simulator cookie stays valid.
    SIMULATOR_COOKIE_TTL = 24 * 60 * 60

    class << self
      # Compare two strings without leaking their contents through timing.
      def secure_compare(a, b)
        ActiveSupport::SecurityUtils.secure_compare(a.to_s, b.to_s)
      end

      # The value to store in the simulator cookie: "timestamp:signature".
      def simulator_cookie(timestamp = Time.now.to_i)
        "#{timestamp}:#{simulator_signature(timestamp)}"
      end

      # A simulator cookie is valid when it carries a recent timestamp signed
      # with the configured simulator secret.
      def valid_simulator_cookie?(cookie)
        return false if FlowChat::Config.simulator_secret.blank? || cookie.blank?

        timestamp_str, signature = cookie.to_s.split(":", 2)
        return false unless timestamp_str && signature

        timestamp = timestamp_str.to_i
        return false if timestamp <= 0
        return false if (Time.now.to_i - timestamp).abs > SIMULATOR_COOKIE_TTL

        secure_compare(signature, simulator_signature(timestamp_str))
      end

      def simulator_signature(timestamp)
        OpenSSL::HMAC.hexdigest(
          OpenSSL::Digest.new("sha256"),
          FlowChat::Config.simulator_secret,
          "simulator:#{timestamp}"
        )
      end
    end
  end
end

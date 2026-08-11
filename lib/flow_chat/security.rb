require "openssl"

begin
  require "active_support/security_utils"
rescue LoadError
  # Older Active Support, or an install without it. secure_compare falls back
  # to its own implementation below.
end

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
        a = a.to_s
        b = b.to_s

        if defined?(ActiveSupport::SecurityUtils)
          ActiveSupport::SecurityUtils.secure_compare(a, b)
        else
          fallback_secure_compare(a, b)
        end
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

      private

      # What Active Support does, for installs that do not have it: compare
      # digests rather than the inputs, so the comparison runs over a fixed
      # length and times neither the contents nor the length of a secret. The
      # equality check afterwards is what makes a digest collision harmless.
      def fallback_secure_compare(a, b)
        digest_a = OpenSSL::Digest.digest("SHA256", a)
        digest_b = OpenSSL::Digest.digest("SHA256", b)

        result = 0
        digest_a.bytes.zip(digest_b.bytes) { |byte_a, byte_b| result |= byte_a ^ byte_b }
        result == 0 && a == b
      end
    end
  end
end

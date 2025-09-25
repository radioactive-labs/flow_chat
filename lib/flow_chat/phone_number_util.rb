module FlowChat
  module PhoneNumberUtil
    class << self
      def to_e164(phone_number)
        return "" if phone_number.nil? || phone_number.empty?

        begin
          # Try to load phonelib without Rails dependency
          require_phonelib_safely
          Phonelib.parse(phone_number).e164
        rescue => e
          FlowChat.logger.warn { "PhoneNumberUtil: Failed to parse phone number '#{phone_number}': #{e.message}" }
          # Fallback to simple formatting if phonelib fails
          fallback_e164_format(phone_number)
        end
      end

      private

      def require_phonelib_safely
        return if defined?(Phonelib)

        # Temporarily stub Rails if it doesn't exist
        if defined?(Rails)
          require "phonelib"
        else
          stub_rails = Module.new do
            def const_missing(name)
              if name == :Railtie
                Class.new
              else
                super
              end
            end
          end
          Object.const_set(:Rails, stub_rails)
          require "phonelib"
          Object.send(:remove_const, :Rails)
        end
      end

      def fallback_e164_format(phone_number)
        # Simple fallback - ensure it starts with + and looks like a phone number
        cleaned = phone_number.to_s.gsub(/[^\d+]/, "")
        cleaned.start_with?("+") ? cleaned : "+#{cleaned}"
      end
    end
  end
end

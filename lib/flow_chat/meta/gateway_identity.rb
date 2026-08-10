module FlowChat
  module Meta
    # What a Meta gateway must say about itself.
    #
    # The behavior modules in this namespace need a handful of the same values:
    # which platform this is, how to name it to a developer, which error class to
    # raise, what to tag logs with. Declaring them here rather than in whichever
    # behavior module happens to be included first means a gateway can include
    # one behavior without the other, and a gateway that forgets a value fails
    # loudly rather than borrowing another platform's.
    #
    # NotImplementedError rather than a default: it descends from ScriptError,
    # not StandardError, so it travels through the bare rescue in
    # SignatureValidation instead of being swallowed into a false return that
    # would read as "invalid signature" and drop every webhook.
    module GatewayIdentity
      def platform
        raise NotImplementedError, "#{self.class.name} must define #platform"
      end

      # The product's name as a developer reading an error message expects it,
      # which is not always the constant: Whatsapp the module, WhatsApp the product.
      def platform_label
        raise NotImplementedError, "#{self.class.name} must define #platform_label"
      end

      def configuration_error_class
        raise NotImplementedError, "#{self.class.name} must define #configuration_error_class"
      end

      # Derived, because every gateway's class name already ends in the tag its
      # logs use. Override only to pin the tag against a class rename.
      def log_tag
        self.class.name.split("::").last
      end
    end
  end
end

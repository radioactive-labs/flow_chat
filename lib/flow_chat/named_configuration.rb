module FlowChat
  # The named-configuration registry every platform's Configuration shares.
  #
  # Storage is a class-level ivar on the including class, not a class variable.
  # A @@configurations in a shared module would give every platform one merged
  # registry, so a name registered for Messenger would resolve for WhatsApp.
  module NamedConfiguration
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def register(name, config)
        FlowChat.logger.debug { "#{self.name}: Registering configuration '#{name}'" }
        configurations[name.to_sym] = config
      end

      def get(name)
        config = configurations[name.to_sym]
        unless config
          FlowChat.logger.error { "#{self.name}: Configuration '#{name}' not found" }
          raise ArgumentError, "#{configuration_label} configuration '#{name}' not found"
        end

        FlowChat.logger.debug { "#{self.name}: Retrieved configuration '#{name}'" }
        config
      end

      def exists?(name)
        configurations.key?(name.to_sym)
      end

      def configuration_names
        configurations.keys
      end

      def clear_all!
        FlowChat.logger.debug { "#{name}: Clearing all registered configurations" }
        configurations.clear
      end

      # The platform's name as it appears in the not-found message. Overridden
      # where the constant name and the product name differ, as with WhatsApp.
      def configuration_label
        name.split("::")[-2]
      end

      private

      # The registry itself is not API. It replaced a @@configurations class
      # variable, which was equally internal, and configuration_names is the
      # public way to ask what is registered.
      def configurations
        @configurations ||= {}
      end
    end

    def register_as(name)
      FlowChat.logger.debug { "#{self.class.name}: Registering configuration as '#{name}'" }
      @name = name.to_sym
      self.class.register(@name, self)
      self
    end
  end
end

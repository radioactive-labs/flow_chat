# frozen_string_literal: true

module UssdEngine
  module Controller
    module Storable
      def self.included(base)
        base.send :extend, StorableClassMethods
      end

      protected

      module StorableClassMethods
        def stores(field)
          instance_prop = "@#{field}"
          key_method_name = "#{field}_key"
          getter_method_name = field
          setter_method_name = "#{field}="
          cache_method_name = "#{field}_cache"
          cache_instance_prop = "@#{cache_method_name}"

          define_method key_method_name do
            File.join ussd_request_id, field
          end

          define_method getter_method_name do
            session[key_method_name]
          end

          define_method setter_method_name do |value|
            session[key_method_name] = value
          end

          define_method setter_method_name do |value|
            session[key_method_name] = value
          end

          define_method cache_method_name do
            unless instance_variable_defined? cache_instance_prop
              instance_variable_set cache_instance_prop, {}
            end
            instance_variable_get cache_instance_prop
          end
        end
      end
    end
  end
end

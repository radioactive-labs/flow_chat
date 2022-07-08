# frozen_string_literal: true

module UssdEngine
  module Controller
    module Storable
      def self.included(base)
        base.send :extend, StorableClassMethods
      end

      protected

      module StorableClassMethods
        def stores(field, accessor = nil, &block)
          instance_prop = "@#{field}"
          key_method_name = "#{field}_key"
          getter_method_name = field
          setter_method_name = "#{field}="

          define_method key_method_name do
            File.join ussd_request_id, field.to_s
          end

          define_method getter_method_name do
            session[send(key_method_name)]
          end

          define_method setter_method_name do |value|
            session[send(key_method_name)] = value
          end

          if accessor.present?
            raise "A block is required if you pass an accessor" unless block_given?

            cache_method_name = "#{accessor}_cache"
            cache_instance_prop = "@#{cache_method_name}"

            define_method cache_method_name do
              unless instance_variable_defined? cache_instance_prop
                instance_variable_set cache_instance_prop, {}
              end
              instance_variable_get cache_instance_prop
            end

            define_method accessor do
              field_value = send(getter_method_name)
              return if field_value.blank?

              send(cache_method_name)[field_value] ||= instance_exec(field_value, &block)
            end
          end
        end
      end
    end
  end
end

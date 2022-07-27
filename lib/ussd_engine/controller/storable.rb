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
          # Given
          # field = :user_id
          instance_prop = "@#{field}" # @user_id
          key_method_name = "#{field}_key" # user_id_key
          getter_method_name = field  # user_id
          setter_method_name = "#{field}="  # user_id=

          # def user_id_key
          #   File.join ussd_request_id, "user_id"
          # end
          define_method key_method_name do
            File.join ussd_request_id, field.to_s
          end

          # def user_id
          #   session[user_id_key]
          # end
          define_method getter_method_name do
            session[send(key_method_name)]
          end

          # def user_id=(value)
          #   session[user_id_key] = value
          # end
          define_method setter_method_name do |value|
            session[send(key_method_name)] = value
          end

          if accessor.present?
            raise "A block is required if you pass an accessor" unless block_given?

            # Given
            # accessor = :user
            cache_method_name = "#{accessor}_cache" # user_cache
            cache_instance_prop = "@#{cache_method_name}" # @user_cache

            # def user_cache
            #   @user_cache ||= {}
            # end
            define_method cache_method_name do
              unless instance_variable_defined? cache_instance_prop
                instance_variable_set cache_instance_prop, {}
              end
              instance_variable_get cache_instance_prop
            end

            # Given
            # block = do |user_id|
            #   User.find user_id
            # end
            #
            # def user
            #   return if user_id.blank?
            #
            #   user_cache[user_id] ||= block(user_id)
            # end
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

module FlowChat
  module Instagram
    module Middleware
      class ChoiceMapper < FlowChat::Messenger::Middleware::ChoiceMapper
        ID_KEY = "instagram.choice_mapping"
        POSITION_KEY = "instagram.position_mapping"

        private

        def platform_limits
          FlowChat::Config.instagram
        end

        # The body always carries numbers here, so a typed number must
        # always resolve, not only above the carousel capacity.
        def always_number?
          true
        end
      end
    end
  end
end

module FlowChat
  module Ussd
    module Middleware
      class ChoiceMapper
        def initialize(app)
          @app = app
          FlowChat.logger.debug { "Ussd::ChoiceMapper: Initialized USSD choice mapping middleware" }
        end

        def call(context)
          @context = context
          @session = context.session

          session_id = context["session.id"]
          FlowChat.logger.debug { "Ussd::ChoiceMapper: Processing request for session #{session_id}" }

          if intercept?
            FlowChat.logger.info { "Ussd::ChoiceMapper: Intercepting request for choice resolution - session #{session_id}" }
            handle_choice_input
          end

          # Clear choice mapping state for new flows
          clear_choice_state_if_needed
          type, prompt, choices, media = @app.call(context)

          if choices.present?
            FlowChat.logger.debug { "Ussd::ChoiceMapper: Found choices, creating number mapping" }
            choices = create_numbered_mapping(choices)
          end

          [type, prompt, choices, media]
        end

        private

        def intercept?
          # Intercept if we have choice mapping state and user input is a number that maps to a choice
          choice_mapping = get_choice_mapping
          should_intercept = choice_mapping.present? &&
            @context.input.present? &&
            choice_mapping.key?(@context.input.to_s)

          if should_intercept
            FlowChat.logger.debug { "Ussd::ChoiceMapper: Intercepting - input: #{@context.input}, mapped to: #{choice_mapping[@context.input.to_s]}" }
          end

          should_intercept
        end

        def handle_choice_input
          choice_mapping = get_choice_mapping
          original_choice = choice_mapping[@context.input.to_s]

          FlowChat.logger.info { "Ussd::ChoiceMapper: Resolving choice input #{@context.input} to #{original_choice}" }

          # Replace the numeric input with the original choice
          @context.input = original_choice
        end

        def create_numbered_mapping(choices)
          # Choices are always a hash after normalize_choices
          numbered_choices = {}
          choice_mapping = {}

          choices.each_with_index do |(key, value), index|
            number = (index + 1).to_s
            numbered_choices[number] = value
            choice_mapping[number] = key.to_s
          end

          store_choice_mapping(choice_mapping)
          FlowChat.logger.debug { "Ussd::ChoiceMapper: Created mapping: #{choice_mapping}" }
          numbered_choices
        end

        def store_choice_mapping(mapping)
          @session.set("ussd.choice_mapping", mapping)
          FlowChat.logger.debug { "Ussd::ChoiceMapper: Stored choice mapping: #{mapping}" }
        end

        def get_choice_mapping
          @session.get("ussd.choice_mapping") || {}
        end

        def clear_choice_mapping
          @session.delete("ussd.choice_mapping")
          FlowChat.logger.debug { "Ussd::ChoiceMapper: Cleared choice mapping" }
        end

        def clear_choice_state_if_needed
          # Clear choice mapping if this is a new flow (no input or fresh start)
          if @context.input.blank? || should_clear_for_new_flow?
            clear_choice_mapping
          end
        end

        def should_clear_for_new_flow?
          # Clear mapping if this input doesn't match any stored mapping
          # This indicates we're in a new flow step
          choice_mapping = get_choice_mapping
          return false if choice_mapping.empty?

          # If input is present but doesn't match any mapping, we're in a new flow
          @context.input.present? && !choice_mapping.key?(@context.input.to_s)
        end
      end
    end
  end
end

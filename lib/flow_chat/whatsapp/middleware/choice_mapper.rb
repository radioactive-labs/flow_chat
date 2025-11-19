require_relative "../id_generator"

module FlowChat
  module Whatsapp
    module Middleware
      # Maps WhatsApp button/list IDs back to original choice keys
      #
      # Similar to USSD::ChoiceMapper, but for WhatsApp interactive messages.
      # WhatsApp uses generated IDs (from IdGenerator) for buttons and list items,
      # and this middleware maps the user's response back to the original choice key.
      #
      # Flow:
      # 1. Flow returns choices with original keys (e.g., {"create" => "Create Account"})
      # 2. Middleware generates WhatsApp-safe IDs from labels
      # 3. Middleware transforms choices to use generated IDs as keys
      # 4. Middleware stores mapping (generated_id → original_key)
      # 5. Renderer receives transformed choices and renders them
      # 6. User selects a button/list item (WhatsApp sends the ID)
      # 7. This middleware intercepts and replaces ID with original key
      # 8. Flow sees the original choice key (not the generated ID)
      #
      # @example
      #   # Flow provides: {"create" => "Create Account"}
      #   # Middleware generates ID: "Create Account"
      #   # Middleware transforms to: {"Create Account" => "Create Account"}
      #   # Middleware stores: {"Create Account" => "create"}
      #   # User clicks, WhatsApp sends: "Create Account"
      #   # Middleware intercepts and maps back to: "create"
      #
      #   # With duplicates: {"yes" => "Accept", "no" => "Accept"}
      #   # IDs generated: "Accept", "Accept 3a4"
      #   # Transformed: {"Accept" => "Accept", "Accept 3a4" => "Accept"}
      #   # Mapping: {"Accept" => "yes", "Accept 3a4" => "no"}
      #   # User clicks second, WhatsApp sends: "Accept 3a4"
      #   # Middleware maps back to: "no"
      #
      class ChoiceMapper
        def initialize(app)
          @app = app
          FlowChat.logger.debug { "Whatsapp::ChoiceMapper: Initialized WhatsApp choice mapping middleware" }
        end

        def call(context)
          @context = context
          @session = context.session

          session_id = context["session.id"]
          FlowChat.logger.debug { "Whatsapp::ChoiceMapper: Processing request for session #{session_id}" }

          if intercept?
            FlowChat.logger.info { "Whatsapp::ChoiceMapper: Intercepting request for choice resolution - session #{session_id}" }
            handle_choice_input
          end

          # Clear choice mapping state for new flows
          clear_choice_state_if_needed

          # Call the app (executor -> flow)
          type, prompt, choices, media = @app.call(context)

          # Transform choices if present (like USSD does)
          if choices.present?
            FlowChat.logger.debug { "Whatsapp::ChoiceMapper: Found choices, creating ID mapping" }
            choices = create_id_mapping(choices)
          end

          [type, prompt, choices, media]
        end

        private

        def intercept?
          # Intercept if we have choice mapping state and user input matches a generated ID
          choice_mapping = get_choice_mapping
          should_intercept = choice_mapping.present? &&
            @context.input.present? &&
            choice_mapping.key?(@context.input.to_s)

          if should_intercept
            FlowChat.logger.debug { "Whatsapp::ChoiceMapper: Intercepting - input: #{@context.input}, mapped to: #{choice_mapping[@context.input.to_s]}" }
          end

          should_intercept
        end

        def handle_choice_input
          choice_mapping = get_choice_mapping
          original_choice = choice_mapping[@context.input.to_s]

          FlowChat.logger.info { "Whatsapp::ChoiceMapper: Resolving choice input #{@context.input} to #{original_choice}" }

          # Replace the generated ID with the original choice key
          @context.input = original_choice
        end

        def create_id_mapping(choices)
          # Choices are always a hash after normalize_choices
          id_generator = IdGenerator.new
          id_choices = {}
          choice_mapping = {}

          choices.each do |key, value|
            # Generate WhatsApp-safe ID from the label
            generated_id = id_generator.generate_id(value.to_s)
            id_choices[generated_id] = value
            choice_mapping[generated_id] = key.to_s
          end

          store_choice_mapping(choice_mapping)
          FlowChat.logger.debug { "Whatsapp::ChoiceMapper: Created mapping: #{choice_mapping}" }
          id_choices
        end

        def store_choice_mapping(mapping)
          @session.set("whatsapp.choice_mapping", mapping)
          FlowChat.logger.debug { "Whatsapp::ChoiceMapper: Stored choice mapping: #{mapping}" }
        end

        def get_choice_mapping
          @session.get("whatsapp.choice_mapping") || {}
        end

        def clear_choice_mapping
          @session.delete("whatsapp.choice_mapping")
          FlowChat.logger.debug { "Whatsapp::ChoiceMapper: Cleared choice mapping" }
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

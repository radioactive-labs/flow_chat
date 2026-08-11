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
      # A button or list row title is truncated to fit (see
      # FlowChat::Whatsapp::Renderer::BUTTON_TITLE_LENGTH /
      # LIST_ROW_TITLE_LENGTH), so a user who types exactly what they see
      # would otherwise fail to match the generated id, which was built from
      # the full label. This middleware additionally registers that
      # on-screen form as an alias for the same choice key, via
      # FlowChat::ChoiceAliasBuilder. When truncation (or a duplicate label)
      # would make titles ambiguous, FlowChat::ChoiceTitles prefixes every
      # title in the set with its position instead, which is what actually
      # keeps them distinct in that case; see its docs for why that decision
      # is made once for the whole set rather than per title.
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

          # The maps belong to exactly one screen: this turn's, if it had a
          # resolvable answer, or one that already fell out of use otherwise.
          # Either way nothing here is still owed to the next screen, so they
          # are cleared unconditionally rather than asked whether they still
          # look "live" - create_id_mapping immediately below repopulates
          # them whenever the app actually returns choices.
          #
          # An earlier version asked should_clear_for_new_flow? that question
          # after handle_choice_input had already rewritten @context.input to
          # the *resolved* value, which can equal one of the map's own keys
          # (an Array choice's key is its label, and IdGenerator can
          # normalize a label to that same string), so the check answered
          # "still live" about a value that was never a fresh reply. That let
          # the maps survive into a free-text screen and reinterpret a typed
          # answer there as the previous menu's choice. This was fixed once
          # here in Task 6 and once for Messenger in Task 13; both fixes had
          # the same shape and the same blind spot, which is why the guard is
          # gone rather than patched a third time.
          clear_choice_state

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

        # Ids are resolved first, then aliases, then positions. Ids can
        # overlap with positions because IdGenerator#normalize_label keeps
        # \w, which includes digits, so a choice labelled "1" generates the
        # id "1". Aliases sit between them: FlowChat::ChoiceAliasBuilder
        # never registers an alias equal to its own choice's generated id
        # (see its docs), so an alias never outranks an id, but it must
        # still beat a position: a typed alias is a match on the title the
        # user actually saw, while a position is a fallback guess from a
        # bare digit that is only shown at all when the screen was numbered.
        def resolved_choice
          input = @context.input.to_s
          get_choice_mapping[input] || get_alias_mapping[input] || get_position_mapping[input]
        end

        def intercept?
          # Intercept if user input matches a generated id or a stored position
          should_intercept = @context.input.present? && resolved_choice.present?

          if should_intercept
            FlowChat.logger.debug { "Whatsapp::ChoiceMapper: Intercepting - input: #{@context.input}, mapped to: #{resolved_choice}" }
          end

          should_intercept
        end

        def handle_choice_input
          original_choice = resolved_choice

          FlowChat.logger.info { "Whatsapp::ChoiceMapper: Resolving choice input #{@context.input} to #{original_choice}" }

          # Replace the generated ID (or typed position) with the original choice key
          @context.input = original_choice
        end

        def create_id_mapping(choices)
          # Choices are always a hash after normalize_choices
          id_generator = FlowChat::IdGenerator.new
          id_choices = {}
          choice_mapping = {}
          generated_ids = {}

          choices.each do |key, value|
            # Generate WhatsApp-safe ID from the label
            generated_id = id_generator.generate_id(value.to_s)
            id_choices[generated_id] = value
            choice_mapping[generated_id] = key.to_s
            generated_ids[key.to_s] = generated_id
          end

          store_choice_mapping(choice_mapping)
          FlowChat.logger.debug { "Whatsapp::ChoiceMapper: Created mapping: #{choice_mapping}" }

          store_alias_mapping(FlowChat::ChoiceAliasBuilder.build(choices, generated_ids, display_title_cap(choices.length)))

          if number_choices?(choices)
            store_position_mapping(choices.keys.map.with_index(1) { |key, i| [i.to_s, key.to_s] }.to_h)
          else
            clear_position_mapping
          end

          id_choices
        end

        # The title cap the renderer will use for these choices, or nil above
        # the list cap, where the renderer falls back to a numbered body and
        # shows the full label (no truncation, so no alias is needed).
        #
        # This repeats the count comparison build_interactive_message makes,
        # because the mapper runs before the renderer and has no way to ask it
        # which rung it chose. WhatsApp's ladder already lives here rather
        # than in FlowChat::Meta::ChoiceLadder (see create_id_mapping's
        # existing MAX_LIST_ROWS comparison above), so this is one more count
        # comparison alongside one already present, not a new kind of
        # duplication.
        def display_title_cap(count)
          if count <= FlowChat::Whatsapp::Renderer::MAX_BUTTONS
            FlowChat::Whatsapp::Renderer::BUTTON_TITLE_LENGTH
          elsif count <= FlowChat::Whatsapp::Renderer::MAX_LIST_ROWS
            FlowChat::Whatsapp::Renderer::LIST_ROW_TITLE_LENGTH
          end
        end

        # A position number is only worth resolving when one is genuinely on
        # screen: above the row cap, where the renderer has no title left to
        # show and numbers the body directly (display_title_cap is nil), or
        # on a button/list rung whose titles FlowChat::ChoiceTitles decided
        # were ambiguous and prefixed with a number. A short, unique set of
        # titles (the common case) shows no number at all, so a typed digit
        # there is free text, not a position.
        def number_choices?(choices)
          cap = display_title_cap(choices.length)
          cap.nil? || FlowChat::ChoiceTitles.ambiguous?(choices, cap)
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

        def store_alias_mapping(mapping)
          @session.set("whatsapp.alias_mapping", mapping)
          FlowChat.logger.debug { "Whatsapp::ChoiceMapper: Stored alias mapping: #{mapping}" }
        end

        def get_alias_mapping
          @session.get("whatsapp.alias_mapping") || {}
        end

        def clear_alias_mapping
          @session.delete("whatsapp.alias_mapping")
        end

        def store_position_mapping(mapping)
          @session.set("whatsapp.position_mapping", mapping)
          FlowChat.logger.debug { "Whatsapp::ChoiceMapper: Stored position mapping: #{mapping}" }
        end

        def get_position_mapping
          @session.get("whatsapp.position_mapping") || {}
        end

        def clear_position_mapping
          @session.delete("whatsapp.position_mapping")
        end

        def clear_choice_state
          clear_choice_mapping
          clear_alias_mapping
          clear_position_mapping
        end
      end
    end
  end
end

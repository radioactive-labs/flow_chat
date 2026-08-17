module FlowChat
  module Whatsapp
    module Middleware
      # Maps what WhatsApp sends back to the choice key the flow branches on.
      #
      # The value on the wire is the title the user was shown, so a tap and a
      # user typing what they read arrive as the same string and resolve
      # through the same map.
      #
      # Flow:
      # 1. Flow returns choices with original keys ({"create" => "Create Account"})
      # 2. This middleware asks FlowChat::ChoiceTitles for each displayed title
      # 3. It re-keys the choices by title and stores title => original key
      # 4. Renderer receives the re-keyed choices and renders them
      # 5. User taps a button, or types the title on it
      # 6. This middleware resolves either back to the original key
      #
      # @example
      #   # Flow provides: {"create" => "Create Account"}
      #   # Titles built:  "Create Account"
      #   # Transformed:   {"Create Account" => "Create Account"}
      #   # Mapping:       {"Create Account" => "create"}
      #
      #   # With duplicates: {"yes" => "Accept", "no" => "Accept"}
      #   # Titles built:  "1. Accept", "2. Accept"
      #   # Mapping:       {"1. Accept" => "yes", "2. Accept" => "no"}
      #
      # A title is truncated to the rung's cap (see
      # FlowChat::Whatsapp::Renderer::BUTTON_TITLE_LENGTH /
      # LIST_ROW_TITLE_LENGTH). When truncation, or a duplicate label, would
      # leave two titles indistinguishable, FlowChat::ChoiceTitles numbers
      # every title in the set instead - which is what keeps them distinct,
      # and why nothing here has to check for collisions itself. See its docs
      # for why that decision is made once for the whole set.
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
          # (an Array choice's key is its label, and the wire value is the
          # title built from that label), so the check answered
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

        # Titles first, then positions. A tap sends the title as its payload
        # and a user who types what they read sends the same string, so both
        # arrive at the same entry - which is why there is no separate alias
        # map any more. A position is the fallback, and only means anything
        # when a number is genuinely on screen; it loses to a title because a
        # choice labelled "1" would otherwise be unreachable.
        def resolved_choice
          input = @context.input.to_s
          get_choice_mapping[input] || get_position_mapping[input]
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

        # The value WhatsApp sends back IS the displayed title.
        # FlowChat::ChoiceTitles guarantees the titles in a set are distinct -
        # numbering the whole set when they would not be - so a title needs no
        # separate id space to be unique in, and there is nothing left for a
        # generated id to collide with.
        #
        # This replaces an id generated by normalizing the label, which was
        # lossy: stripping "!" turned "Yes!" into the id "Yes", which was
        # another choice's label verbatim, and the id map was consulted before
        # the alias map. Titles are also bounded by the rung's cap (20 button,
        # 24 list row), comfortably inside WhatsApp's id caps of 256 and 200.
        def create_id_mapping(choices)
          cap = display_title_cap(choices.length)
          return passthrough_mapping(choices) if cap.nil?

          title_choices = {}
          choice_mapping = {}

          FlowChat::ChoiceTitles.build(choices, cap).each do |key, label, title, _truncated|
            title_choices[title] = label
            choice_mapping[title] = key
          end

          store_choice_mapping(choice_mapping)

          if number_choices?(choices)
            store_position_mapping(choices.keys.map.with_index(1) { |key, i| [i.to_s, key.to_s] }.to_h)
          else
            clear_position_mapping
          end

          title_choices
        end

        # Above the row cap the renderer numbers the body and prints each full
        # label beside its number, so the label itself is what is on screen and
        # stays resolvable - nothing is truncated, so there is no shortened
        # form to key on instead.
        #
        # A label shared by two choices is dropped rather than resolved to the
        # first of them. It identifies neither on a screen that shows both, and
        # the number printed next to each is the reply that does.
        def passthrough_mapping(choices)
          labels = choices.map { |key, label| [label.to_s, key.to_s] }
          repeated = labels.map(&:first).tally

          store_choice_mapping(labels.reject { |label, _| repeated[label] > 1 }.to_h)
          store_position_mapping(choices.keys.map.with_index(1) { |key, i| [i.to_s, key.to_s] }.to_h)
          choices
        end

        # The title cap the renderer will use for these choices, or nil above
        # the list cap, where the renderer falls back to a numbered body and
        # shows the full label (no truncation, so no alias is needed).
        #
        # Goes through FlowChat::Meta::ChoiceLadder, the same helper
        # FlowChat::Whatsapp::Renderer#build_interactive_message consults
        # (via FlowChat::Config.whatsapp#ladder_limits), rather than
        # re-deriving the rung from its own count comparisons: the mapper
        # runs before the renderer and has no way to ask it which rung it
        # chose, so both asking the same shared helper is what keeps them
        # from disagreeing, the same reason Messenger's mapper does this too.
        def display_title_cap(count)
          case FlowChat::Meta::ChoiceLadder.rung_for(count, FlowChat::Config.whatsapp.ladder_limits)
          when :quick_replies then FlowChat::Whatsapp::Renderer::BUTTON_TITLE_LENGTH
          when :carousel then FlowChat::Whatsapp::Renderer::LIST_ROW_TITLE_LENGTH
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
          clear_position_mapping
        end
      end
    end
  end
end

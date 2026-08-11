module FlowChat
  module Messenger
    module Middleware
      # Maps a reply back to the choice key the flow used.
      #
      # Three key spaces can be live at once. A tap sends the payload id the
      # renderer put on the button; a user who instead types the (possibly
      # truncated) title they see on that button types an alias; and on the
      # numbered rung a typed digit sends a position. They are stored
      # separately and resolved ids first, then aliases, then positions,
      # because the spaces overlap: IdGenerator keeps digits, so a choice
      # labelled "1" generates the id "1", which is not necessarily the first
      # choice, and FlowChat::ChoiceAliasBuilder only ever registers an alias
      # that differs from every generated id, so ids can never lose to one.
      class ChoiceMapper
        ID_KEY = "messenger.choice_mapping"
        ALIAS_KEY = "messenger.alias_mapping"
        POSITION_KEY = "messenger.position_mapping"

        def initialize(app)
          @app = app
          FlowChat.logger.debug { "#{self.class.name}: Initialized" }
        end

        def call(context)
          @context = context
          @session = context.session

          handle_choice_input if intercept?

          # Clear stale mapping state for a new flow step. All three maps are
          # cleared together: create_mappings only runs when a screen HAS
          # choices, so a screen without them clears nothing unless clearing
          # is explicit here. Leaving one map behind would let it hijack a
          # later turn, e.g. a position map surviving a numbered menu
          # rewriting a typed "3" on the next free-text screen into that
          # menu's third choice key. This was a real bug in the WhatsApp
          # mapper, found and fixed in Task 6.
          clear_mappings_if_needed

          type, prompt, choices, media = @app.call(context)

          choices = create_mappings(choices) if choices.present?

          [type, prompt, choices, media]
        end

        private

        def platform_limits
          FlowChat::Config.messenger
        end

        def always_number?
          false
        end

        def id_key
          self.class::ID_KEY
        end

        def alias_key
          self.class::ALIAS_KEY
        end

        def position_key
          self.class::POSITION_KEY
        end

        def get_id_mapping
          @session.get(id_key) || {}
        end

        def get_alias_mapping
          @session.get(alias_key) || {}
        end

        def get_position_mapping
          @session.get(position_key) || {}
        end

        # Ids are resolved first, then aliases, then positions. Ids can
        # overlap with positions because IdGenerator#normalize_label keeps
        # \w, which includes digits, so a choice labelled "1" generates the
        # id "1". Aliases sit between them because they are only ever
        # registered when they differ from every generated id (see
        # FlowChat::ChoiceAliasBuilder), so they cannot outrank one, but they
        # must still beat a position: a typed alias is a match on what the
        # user actually saw, while a position is a fallback guess from a
        # digit.
        def resolved_choice
          input = @context.input.to_s
          return nil if input.empty?

          get_id_mapping[input] || get_alias_mapping[input] || get_position_mapping[input]
        end

        def intercept?
          @context.input.present? && resolved_choice.present?
        end

        def handle_choice_input
          original = resolved_choice
          FlowChat.logger.info { "#{self.class.name}: Resolving input #{@context.input} to #{original}" }
          @context.input = original
        end

        def clear_mappings_if_needed
          if @context.input.blank? || stale_mappings?
            @session.delete(id_key)
            @session.delete(alias_key)
            @session.delete(position_key)
          end
        end

        # True once the current input no longer names a live mapping entry,
        # which is the signal that the flow has moved past the screen the
        # mappings were built for.
        def stale_mappings?
          id_mapping = get_id_mapping
          alias_mapping = get_alias_mapping
          position_mapping = get_position_mapping
          return false if id_mapping.empty? && alias_mapping.empty? && position_mapping.empty?

          input = @context.input.to_s
          input.present? && !id_mapping.key?(input) && !alias_mapping.key?(input) && !position_mapping.key?(input)
        end

        def create_mappings(choices)
          generator = FlowChat::IdGenerator.new(max_length: 1000)
          id_choices = {}
          id_mapping = {}
          generated_ids = {}

          choices.each do |key, label|
            generated_id = generator.generate_id(label.to_s)
            id_choices[generated_id] = label
            id_mapping[generated_id] = key.to_s
            generated_ids[key.to_s] = generated_id
          end

          @session.set(id_key, id_mapping)
          @session.set(alias_key, FlowChat::ChoiceAliasBuilder.build(choices, generated_ids, display_title_cap(choices.length)))

          if FlowChat::Meta::ChoiceLadder.numbers_in_body?(choices.length, platform_limits, always_number: always_number?)
            @session.set(position_key, choices.keys.map.with_index(1) { |key, i| [i.to_s, key.to_s] }.to_h)
          else
            @session.delete(position_key)
          end

          id_choices
        end

        # The title cap the renderer will use for these choices, or nil on
        # the numbered rung, where the renderer shows the full label with no
        # truncation, so no alias is needed. This calls the same
        # FlowChat::Meta::ChoiceLadder the renderer consults, so the two
        # cannot drift on which rung a given count lands on.
        def display_title_cap(count)
          case FlowChat::Meta::ChoiceLadder.rung_for(count, platform_limits)
          when :quick_replies then platform_limits.max_quick_reply_title
          when :carousel then platform_limits.max_button_title
          end
        end
      end
    end
  end
end

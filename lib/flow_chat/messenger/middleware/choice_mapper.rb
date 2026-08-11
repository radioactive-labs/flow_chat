module FlowChat
  module Messenger
    module Middleware
      # Maps a reply back to the choice key the flow used.
      #
      # Three key spaces can be live at once. A tap sends the payload id the
      # renderer put on the button; a user who instead types the title they
      # see on that button types an alias; and, only when a number is
      # genuinely on screen, a typed digit sends a position. They are stored
      # separately and resolved ids first, then aliases, then positions,
      # because the spaces overlap: IdGenerator keeps digits, so a choice
      # labelled "1" generates the id "1", which is not necessarily the first
      # choice, and FlowChat::ChoiceTitles.aliases_for never registers an
      # alias equal to its own choice's generated id, so ids can never lose
      # to one.
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

          # The maps belong to exactly one screen: this turn's, if it had a
          # resolvable answer, or one that already fell out of use otherwise.
          # Either way nothing here is still owed to the next screen, so they
          # are cleared unconditionally rather than asked whether they still
          # look "live" - create_mappings immediately below repopulates them
          # whenever the app actually returns choices.
          #
          # An earlier version asked stale_mappings? that question after
          # handle_choice_input had already rewritten @context.input to the
          # *resolved* value, which can equal one of the map's own keys (an
          # Array choice's key is its label, and IdGenerator can normalize a
          # label to that same string), so the check answered "still live"
          # about a value that was never a fresh reply. That let the maps
          # survive into a free-text screen and reinterpret a typed answer
          # there as the previous menu's choice. This was fixed once for
          # WhatsApp in Task 6 and once here in Task 13; both fixes had the
          # same shape and the same blind spot, which is why the guard is
          # gone rather than patched a third time.
          clear_mappings

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
        # id "1". Aliases sit between them: FlowChat::ChoiceTitles.aliases_for
        # never registers an alias equal to its own choice's generated id
        # (see its docs), so an alias never outranks an id, but it must
        # still beat a position: a typed alias is a match on the title the
        # user actually saw, while a position is a fallback guess from a
        # bare digit that is only shown at all when the screen was numbered.
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

        def clear_mappings
          @session.delete(id_key)
          @session.delete(alias_key)
          @session.delete(position_key)
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
          @session.set(alias_key, FlowChat::ChoiceTitles.aliases_for(choices, generated_ids, display_title_cap(choices.length)))

          if number_choices?(choices)
            @session.set(position_key, choices.keys.map.with_index(1) { |key, i| [i.to_s, key.to_s] }.to_h)
          else
            @session.delete(position_key)
          end

          id_choices
        end

        # The title cap the renderer will use for these choices, or nil on
        # the :none and :numbered rungs, where there is no separate title to
        # alias: :none has no choices, and :numbered already lists each full
        # label next to its number straight in the body, with nothing more
        # to truncate. This calls the same FlowChat::Meta::ChoiceLadder the
        # renderer consults, so the two cannot drift on which rung a given
        # count lands on.
        def display_title_cap(count)
          case FlowChat::Meta::ChoiceLadder.rung_for(count, platform_limits)
          when :quick_replies then platform_limits.max_quick_reply_title
          when :carousel then platform_limits.max_button_title
          end
        end

        # A position number is only worth resolving when one is genuinely on
        # screen: on the :numbered rung, or wherever always_number? forces
        # the renderer's #body to list one regardless of rung (Instagram,
        # for a desktop user with no tappable surface at all), or on a
        # quick-reply/carousel rung whose titles FlowChat::ChoiceTitles
        # decided were ambiguous and prefixed with a number. always_number?
        # only ever governs that body listing; it says nothing about whether
        # a title itself was numbered, so it cannot answer this alone.
        def number_choices?(choices)
          count = choices.length
          return true if FlowChat::Meta::ChoiceLadder.numbers_in_body?(count, platform_limits, always_number: always_number?)

          FlowChat::ChoiceTitles.ambiguous?(choices, display_title_cap(count))
        end
      end
    end
  end
end

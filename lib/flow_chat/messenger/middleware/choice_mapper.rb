module FlowChat
  module Messenger
    module Middleware
      # Maps a reply back to the choice key the flow used.
      #
      # Two key spaces can be live at once. A tap sends the payload the
      # renderer put on the button, which is the title shown on it, and a user
      # who types what they read sends that same string - so both resolve
      # through one map. Only when a number is genuinely on screen does a
      # typed digit mean a position, which is the second space.
      #
      # The title is the payload rather than a separately generated id
      # because FlowChat::ChoiceTitles already guarantees the titles in a set
      # are distinct, numbering the set when they would not be. A generated
      # id needed its own uniqueness rule, and the one it had was lossy: it
      # stripped punctuation, so "Yes!" produced the id "Yes", which was
      # another choice's label exactly.
      class ChoiceMapper
        ID_KEY = "messenger.choice_mapping"
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
          # Array choice's key is its label, and the wire value is the title
          # built from that label), so the check answered "still live"
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

        def position_key
          self.class::POSITION_KEY
        end

        def get_id_mapping
          @session.get(id_key) || {}
        end

        def get_position_mapping
          @session.get(position_key) || {}
        end

        # Titles first, then positions. A tap sends the title as its payload
        # and a user typing what they read sends the same string, so both
        # land on the same entry. A position must lose to a title, because a
        # choice labelled "1" would otherwise be unreachable: its title is
        # "1", and a bare digit is only a position when the screen was
        # numbered at all.
        def resolved_choice
          input = @context.input.to_s
          return nil if input.empty?

          get_id_mapping[input] || get_position_mapping[input]
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
          @session.delete(position_key)
        end

        def create_mappings(choices)
          cap = display_title_cap(choices.length)
          return passthrough_mapping(choices) if cap.nil?

          title_choices = {}
          id_mapping = {}

          FlowChat::ChoiceTitles.build(choices, cap).each do |key, label, title, _truncated|
            title_choices[title] = label
            id_mapping[title] = key
          end

          @session.set(id_key, id_mapping)

          if number_choices?(choices)
            @session.set(position_key, choices.keys.map.with_index(1) { |key, i| [i.to_s, key.to_s] }.to_h)
          else
            @session.delete(position_key)
          end

          title_choices
        end

        # On the :numbered rung the body already prints each full label beside
        # its number, so the label itself is what is on screen and stays
        # resolvable - nothing is truncated, so there is no shortened form to
        # key on instead.
        #
        # A label shared by two choices is dropped rather than resolved to the
        # first of them. It identifies neither on a screen that shows both, and
        # the number printed next to each is the reply that does.
        def passthrough_mapping(choices)
          labels = choices.map { |key, label| [label.to_s, key.to_s] }
          repeated = labels.map(&:first).tally

          @session.set(id_key, labels.reject { |label, _| repeated[label] > 1 }.to_h)
          @session.set(position_key, choices.keys.map.with_index(1) { |key, i| [i.to_s, key.to_s] }.to_h)
          choices
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

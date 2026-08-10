module FlowChat
  module Messenger
    module Middleware
      # Maps a reply back to the choice key the flow used.
      #
      # Two key spaces can be live at once. A tap sends the payload id the
      # renderer put on the button, and on the numbered rung a typed digit sends
      # a position. They are stored separately and resolved ids first, because
      # the spaces overlap: IdGenerator keeps digits, so a choice labelled "1"
      # generates the id "1", which is not necessarily the first choice.
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

          # Clear stale mapping state for a new flow step. Both maps are
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

        def position_key
          self.class::POSITION_KEY
        end

        def get_id_mapping
          @session.get(id_key) || {}
        end

        def get_position_mapping
          @session.get(position_key) || {}
        end

        # Ids are resolved before positions because the two key spaces can
        # overlap: IdGenerator#normalize_label keeps \w, which includes digits,
        # so a choice labelled "1" generates the id "1".
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

        def clear_mappings_if_needed
          if @context.input.blank? || stale_mappings?
            @session.delete(id_key)
            @session.delete(position_key)
          end
        end

        # True once the current input no longer names a live mapping entry,
        # which is the signal that the flow has moved past the screen the
        # mappings were built for.
        def stale_mappings?
          id_mapping = get_id_mapping
          position_mapping = get_position_mapping
          return false if id_mapping.empty? && position_mapping.empty?

          input = @context.input.to_s
          input.present? && !id_mapping.key?(input) && !position_mapping.key?(input)
        end

        def create_mappings(choices)
          generator = FlowChat::IdGenerator.new(max_length: 1000)
          id_choices = {}
          id_mapping = {}

          choices.each do |key, label|
            generated_id = generator.generate_id(label.to_s)
            id_choices[generated_id] = label
            id_mapping[generated_id] = key.to_s
          end

          @session.set(id_key, id_mapping)

          if FlowChat::Meta::ChoiceLadder.numbers_in_body?(choices.length, platform_limits, always_number: always_number?)
            @session.set(position_key, choices.keys.map.with_index(1) { |key, i| [i.to_s, key.to_s] }.to_h)
          else
            @session.delete(position_key)
          end

          id_choices
        end
      end
    end
  end
end

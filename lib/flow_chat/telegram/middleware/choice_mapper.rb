module FlowChat
  module Telegram
    module Middleware
      # Maps a Telegram reply back to the choice key the flow branches on.
      #
      # callback_data is 1-64 *bytes*, not characters, and carries no
      # character restrictions - Telegram types it as a byte string. Two
      # things followed from sizing it in characters instead:
      #
      # - a label with multibyte characters overflowed the field and was
      #   rejected by the API, because 64 characters of CJK or emoji is far
      #   more than 64 bytes;
      # - two labels sharing their first 64 characters were cut to the same
      #   callback_data, which then matched neither key and failed the flow's
      #   own validation, so the choice could not be picked at all.
      #
      # Both are gone once the titles are built to a byte budget and a set
      # that would collide under that budget is numbered. Numbering is what
      # keeps them apart, and it works here for the same reason it works
      # everywhere else: a position prefix sits at the front and survives a
      # cut from the right, where a suffix would be the first thing lost.
      class ChoiceMapper
        SESSION_KEY = "telegram.choice_mapping"
        POSITION_KEY = "telegram.position_mapping"

        # https://core.telegram.org/bots/api#inlinekeyboardbutton
        CALLBACK_DATA_LIMIT = 64

        def initialize(app)
          @app = app
          FlowChat.logger.debug { "Telegram::ChoiceMapper: Initialized" }
        end

        def call(context)
          @context = context
          @session = context.session

          resolve_input

          response = @app.call(context)
          return response unless response

          type, prompt, choices, media = response
          choices = remember(choices) if choices.present?

          [type, prompt, choices, media]
        end

        private

        # Titles first, then positions. A tap sends the title as its
        # callback_data and a user typing what they read sends the same
        # string, so both land on the same entry. A position must lose to a
        # title, or a choice labelled "1" could never be picked.
        def resolve_input
          return if @session.nil? || @context.input.blank?

          input = @context.input.to_s
          resolved = mapping[input] || positions[input]
          return unless resolved

          FlowChat.logger.info { "Telegram::ChoiceMapper: Resolving #{input} to #{resolved}" }
          @context.input = resolved
        end

        def remember(choices)
          return choices unless @session && choices.is_a?(Hash)

          wire_choices = {}
          choice_mapping = {}

          titles = FlowChat::ChoiceTitles.build(choices, CALLBACK_DATA_LIMIT, measure: :bytes)

          titles.each do |key, _label, title, _truncated|
            wire_choices[title] = title
            choice_mapping[title] = key
          end

          @session.set(SESSION_KEY, choice_mapping)
          @session.set(POSITION_KEY, choices.keys.map.with_index(1) { |key, i| [i.to_s, key.to_s] }.to_h)

          FlowChat.logger.debug { "Telegram::ChoiceMapper: Created mapping: #{choice_mapping}" }
          wire_choices
        end

        def mapping
          @session.get(SESSION_KEY) || {}
        end

        def positions
          @session.get(POSITION_KEY) || {}
        end
      end
    end
  end
end

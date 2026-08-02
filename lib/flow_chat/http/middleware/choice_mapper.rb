module FlowChat
  module Http
    module Middleware
      # Maps a web client's reply back to the choice it belongs to.
      #
      # A web client renders the choices itself, so what it sends back is
      # whatever it decided to send: the key it was given, or the label it
      # actually put on the button. Sending the label is the better of the two,
      # because a transcript then reads back as what the visitor pressed rather
      # than as an internal id, but the flow branches on keys.
      #
      # So both are accepted. Unlike the numbering mappers, this one leaves the
      # choices exactly as the flow returned them, since the client is rendering
      # them and does not need them rewritten.
      class ChoiceMapper
        SESSION_KEY = "http.choice_mapping"

        def initialize(app)
          @app = app
          FlowChat.logger.debug { "Http::ChoiceMapper: Initialized HTTP choice mapping middleware" }
        end

        def call(context)
          resolve_input(context)

          type, prompt, choices, media = @app.call(context)

          remember(context, choices)

          [type, prompt, choices, media]
        end

        private

        def resolve_input(context)
          return if context.input.blank?

          mapping = context.session.get(SESSION_KEY) || {}
          return if mapping.empty?

          matched = mapping[context.input.to_s.strip.downcase]
          return unless matched

          FlowChat.logger.info { "Http::ChoiceMapper: Resolving #{context.input} to #{matched}" }
          context.input = matched
        end

        # Label to key. Cleared once a question carries no choices, so an answer
        # to a later question is never read as a choice from an earlier one.
        #
        # Duplicated labels are indistinguishable to whoever is reading them, so
        # the first wins, as it does on the screen.
        def remember(context, choices)
          if choices.blank?
            context.session.delete(SESSION_KEY)
            return
          end

          mapping = {}
          choices.each do |key, label|
            mapping[label.to_s.strip.downcase] ||= key.to_s
          end

          context.session.set(SESSION_KEY, mapping)
          FlowChat.logger.debug { "Http::ChoiceMapper: Created mapping: #{mapping}" }
        end
      end
    end
  end
end

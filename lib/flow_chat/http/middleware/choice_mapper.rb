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
      # So both are accepted. Nothing is truncated here - the client decides
      # its own widths - so a set of distinct labels is passed through exactly
      # as the flow wrote it.
      #
      # Matching is exact, with no normalization on either side. A client
      # echoes back the string it was handed rather than a person typing it,
      # so nothing drifts on the way - and every transform that could have
      # absorbed such a drift can also merge two choices into one entry, which
      # is how the second of a pair became unpickable in the first place.
      #
      # The one thing that does get rewritten is a set whose labels are
      # identical. Two choices both labelled "Savings" cannot be told apart by
      # a visitor reading them either, so FlowChat::ChoiceTitles numbers the
      # whole set. Previously the second simply lost to the first
      # (`mapping[label] ||= key`) and could not be picked at all.
      class ChoiceMapper
        SESSION_KEY = "http.choice_mapping"

        # The client renders these, so there is no platform width to fit.
        UNCAPPED = Float::INFINITY

        def initialize(app)
          @app = app
          FlowChat.logger.debug { "Http::ChoiceMapper: Initialized HTTP choice mapping middleware" }
        end

        def call(context)
          resolve_input(context)

          type, prompt, choices, media = @app.call(context)

          choices = remember(context, choices)

          [type, prompt, choices, media]
        end

        private

        def resolve_input(context)
          return if context.input.blank?

          mapping = context.session.get(SESSION_KEY) || {}
          return if mapping.empty?

          matched = mapping[context.input.to_s]
          return unless matched

          FlowChat.logger.info { "Http::ChoiceMapper: Resolving #{context.input} to #{matched}" }
          context.input = matched
        end

        # Displayed title to key. Cleared once a question carries no choices, so
        # an answer to a later question is never read as a choice from an
        # earlier one.
        #
        # Labels that survive the fold distinctly are returned untouched, which
        # is the ordinary case. Only a set that would collide under the fold is
        # numbered, and then the numbered titles are what the client is given -
        # so what the visitor reads is what this resolves.
        #
        # @return [Hash, nil] the choices to render
        def remember(context, choices)
          if choices.blank?
            context.session.delete(SESSION_KEY)
            return choices
          end

          mapping = {}
          titled = {}

          FlowChat::ChoiceTitles.build(choices, UNCAPPED).each do |key, _label, title, _truncated|
            titled[key] = title
            mapping[title] = key
          end

          context.session.set(SESSION_KEY, mapping)
          FlowChat.logger.debug { "Http::ChoiceMapper: Created mapping: #{mapping}" }
          titled
        end
      end
    end
  end
end

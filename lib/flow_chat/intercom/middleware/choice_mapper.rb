module FlowChat
  module Intercom
    module Middleware
      # Maps an Intercom reply back to the choice it belongs to.
      #
      # Intercom does support real quick_reply buttons now, tagged with a uuid
      # that comes back on the tap in the webhook's quick_reply_uuid - the most
      # reliable handle when it's there. The renderer hands the uuid the same
      # number this middleware already assigned (it never sees the flow's own
      # key - see remember, below, and Renderer#build_interactive_message), so
      # a tapped uuid and a typed number resolve through the very same session
      # entry. But that field's exact path in a real delivery is unverified,
      # and the renderer still writes the options out as a numbered list too,
      # so this middleware keeps resolving a typed number or label the same way
      # it always has, as the fallback that must keep working either way.
      #
      # The words are accepted too. Nothing stops someone typing "Sales" instead
      # of "2", and on a channel where they are typing into a text box rather
      # than pressing a button, plenty will.
      #
      # Flow:
      # 1. Flow returns choices with their own keys (e.g. {"sales" => "Sales"})
      # 2. This middleware numbers them and remembers what each number and
      #    label meant
      # 3. The renderer writes "1. Sales" and sends a quick_reply tagged "1"
      # 4. The reader taps the button (quick_reply_uuid "1" comes back) or
      #    types "1" or "Sales"
      # 5. This middleware turns whichever arrived back into "sales"
      # 6. The flow sees its own key
      class ChoiceMapper
        SESSION_KEY = "intercom.choice_mapping"

        def initialize(app)
          @app = app
          FlowChat.logger.debug { "Intercom::ChoiceMapper: Initialized Intercom choice mapping middleware" }
        end

        def call(context)
          @context = context
          @session = context.session

          resolve_input

          type, prompt, choices, media = @app.call(context)

          choices = remember(choices) if choices.present?

          [type, prompt, choices, media]
        end

        private

        def resolve_input
          mapping = @session.get(SESSION_KEY) || {}
          return if mapping.empty?

          uuid = @context["intercom.quick_reply_uuid"]
          if uuid.present? && (matched = mapping[uuid.to_s])
            FlowChat.logger.info { "Intercom::ChoiceMapper: Resolving quick_reply_uuid #{uuid} to #{matched}" }
            @context.input = matched
            return
          end

          return if @context.input.blank?

          matched = mapping[@context.input.to_s.strip.downcase]
          return unless matched

          FlowChat.logger.info { "Intercom::ChoiceMapper: Resolving #{@context.input} to #{matched}" }
          @context.input = matched
        end

        # Numbers the choices and stores what each number and each label
        # meant. The renderer sends this same number back out as the
        # quick_reply's uuid (it only ever sees the numbered hash returned
        # below, never the flow's own key), so a tapped uuid resolves through
        # the identical "number" entry a typed number would.
        #
        # Duplicated labels are indistinguishable to whoever is reading them,
        # so the first wins, as it does on the screen. Their numbers still
        # differ.
        def remember(choices)
          numbered = {}
          mapping = {}

          choices.each_with_index do |(key, label), index|
            number = (index + 1).to_s
            numbered[number] = label
            mapping[number] = key.to_s
            mapping[label.to_s.strip.downcase] ||= key.to_s
          end

          @session.set(SESSION_KEY, mapping)
          FlowChat.logger.debug { "Intercom::ChoiceMapper: Created mapping: #{mapping}" }
          numbered
        end
      end
    end
  end
end

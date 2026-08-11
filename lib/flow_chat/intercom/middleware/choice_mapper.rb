module FlowChat
  module Intercom
    module Middleware
      # Maps an Intercom reply back to the choice it belongs to.
      #
      # Intercom has no interactive buttons, so the renderer writes the options
      # out as a numbered list and asks the reader to reply with a number. That
      # number has to come back to the choice key the flow branches on, the same
      # job USSD's mapper does for a handset.
      #
      # The words are accepted too. Nothing stops someone typing "Sales" instead
      # of "2", and on a channel where they are typing into a text box rather
      # than pressing a button, plenty will.
      #
      # Flow:
      # 1. Flow returns choices with their own keys (e.g. {"sales" => "Sales"})
      # 2. This middleware numbers them and remembers what each number meant
      # 3. The renderer writes "1. Sales" and asks for a number
      # 4. The reader replies "1", or "Sales"
      # 5. This middleware turns either back into "sales"
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
          return if @context.input.blank?

          mapping = @session.get(SESSION_KEY) || {}
          return if mapping.empty?

          matched = mapping[@context.input.to_s.strip.downcase]
          return unless matched

          FlowChat.logger.info { "Intercom::ChoiceMapper: Resolving #{@context.input} to #{matched}" }
          @context.input = matched
        end

        # Numbers the choices and stores what each number and each label meant.
        # Duplicated labels are indistinguishable to whoever is reading them, so
        # the first wins, as it does on the screen. Their numbers still differ.
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

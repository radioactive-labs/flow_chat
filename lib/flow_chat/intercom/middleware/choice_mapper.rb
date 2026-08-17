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
      # A number is the only thing that resolves, as on USSD, and that is what
      # the message asks for in as many words. It is also what makes this
      # mapper safe by construction rather than by care: positions are unique
      # whatever the labels say, so there is no equivalence under which two
      # choices could collapse and nothing to check them against.
      #
      # Labels were matched too, case insensitively. That is what needed the
      # care - two choices reading the same, or differing only in case, folded
      # onto one entry and the second could not be picked by name at all. On a
      # screen that prints a number beside every option and asks for one, the
      # number already does that job unambiguously.
      #
      # Flow:
      # 1. Flow returns choices with their own keys (e.g. {"sales" => "Sales"})
      # 2. This middleware numbers them and remembers what each number meant
      # 3. The renderer writes "1. Sales" and asks for a number
      # 4. The reader replies "1"
      # 5. This middleware turns it back into "sales"
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

          choices = remember(choices)

          [type, prompt, choices, media]
        end

        private

        def resolve_input
          return if @context.input.blank?

          mapping = @session.get(SESSION_KEY) || {}
          return if mapping.empty?

          # Surrounding whitespace is trimmed off a chat message before the
          # lookup. Unlike a fold over labels, this cannot merge two choices:
          # trimming leaves "1" and "2" as distinct as it found them.
          matched = mapping[@context.input.to_s.strip]
          return unless matched

          FlowChat.logger.info { "Intercom::ChoiceMapper: Resolving #{@context.input} to #{matched}" }
          @context.input = matched
        end

        # Numbers the choices and stores what each number meant.
        #
        # The renderer is what prints the number beside each label, so nothing
        # is prefixed here - doing both would read as "1. 1. Savings".
        #
        # Cleared when a screen carries no choices, so an answer typed into a
        # later free-text question is never read as a choice from an earlier
        # menu. WhatsApp and Messenger each had this same bug fixed twice.
        #
        # @return [Hash, nil] the choices to render
        def remember(choices)
          if choices.blank?
            @session.delete(SESSION_KEY)
            return choices
          end

          numbered = {}
          mapping = {}

          choices.each_with_index do |(key, label), index|
            number = (index + 1).to_s
            numbered[number] = label.to_s
            mapping[number] = key.to_s
          end

          @session.set(SESSION_KEY, mapping)
          FlowChat.logger.debug { "Intercom::ChoiceMapper: Created mapping: #{mapping}" }
          numbered
        end
      end
    end
  end
end

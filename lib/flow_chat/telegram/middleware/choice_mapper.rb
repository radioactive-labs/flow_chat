module FlowChat
  module Telegram
    module Middleware
      class ChoiceMapper
        def initialize(app)
          @app = app
        end

        def call(context)
          input = context.input

          # Check if input matches a stored choice key (for validation/logging)
          if context.session && input.present?
            choices = context.session.get("telegram_choices")
            if choices&.key?(input)
              FlowChat.logger.debug { "ChoiceMapper: Input '#{input}' is a valid choice key" }
            end
          end

          response = @app.call(context)

          # Store choices in session for validation
          if response
            _, _, choices, _ = response
            if choices.is_a?(Hash)
              context.session&.set("telegram_choices", choices)
            end
          end

          response
        end
      end
    end
  end
end

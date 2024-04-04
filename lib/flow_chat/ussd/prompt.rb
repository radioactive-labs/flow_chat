module FlowChat
  module Ussd
    class Prompt
      attr_reader :user_input

      def initialize(input)
        @user_input = input
      end

      def ask(msg, choices: nil, convert: nil, validate: nil, transform: nil)
        if user_input.present?
          input = user_input
          input = convert.call(input) if convert.present?
          validation_error = validate.call(input) if validate.present?

          prompt!([validation_error, msg].join("\n\n"), choices:) if validation_error.present?

          input = transform.call(input) if transform.present?
          return input
        end

        prompt! msg, choices:
      end

      def say(message)
        terminate! message
      end

      def select(msg, choices)
        choices, choices_prompt = build_select_choices choices
        ask(
          msg,
          choices: choices_prompt,
          convert: lambda { |choice| choice.to_i },
          validate: lambda { |choice| "Invalid selection:" unless (1..choices.size).include?(choice) },
          transform: lambda { |choice| choices[choice - 1] }
        )
      end

      def yes?(msg)
        select(msg, ["Yes", "No"]) == "Yes"
      end

      private

      def build_select_choices(choices)
        case choices
        when Array
          choices_prompt = choices.map.with_index { |c, i| [i + 1, c] }.to_h
        when Hash
          choices_prompt = choices.values.map.with_index { |c, i| [i + 1, c] }.to_h
          choices = choices.keys
        else
          raise ArgumentError, "choices must be an array or hash"
        end
        [choices, choices_prompt]
      end

      def prompt!(msg, choices:)
        raise FlowChat::Interrupt::Prompt.new(msg, choices:)
      end

      def terminate!(msg)
        raise FlowChat::Interrupt::Terminate.new(msg)
      end
    end
  end
end

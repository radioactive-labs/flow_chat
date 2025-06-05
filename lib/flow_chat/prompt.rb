module FlowChat
  class Prompt
    attr_reader :user_input

    def initialize(input)
      @user_input = input
    end

    def ask(msg, choices: nil, convert: nil, validate: nil, transform: nil, media: nil)
      # Validate media and choices compatibility
      validate_media_choices_compatibility(media, choices)

      if user_input.present?
        input = user_input
        input = convert.call(input) if convert.present?
        validation_error = validate.call(input) if validate.present?

        if validation_error.present?
          # Use config to determine whether to combine validation error with original message
          message = if FlowChat::Config.combine_validation_error_with_message
            [validation_error, msg].join("\n\n")
          else
            validation_error
          end
          prompt!(message, choices: choices, media: media)
        end

        input = transform.call(input) if transform.present?
        return input
      end

      # Pass raw message and media separately to the renderer
      prompt! msg, choices: choices, media: media
    end

    def say(message, media: nil)
      # Pass raw message and media separately to the renderer
      terminate! message, media: media
    end

    def select(msg, choices, media: nil)
      # Validate media and choices compatibility
      validate_media_choices_compatibility(media, choices)

      choices, choices_prompt = build_select_choices choices
      ask(
        msg,
        choices: choices_prompt,
        convert: lambda { |choice| choice.to_i },
        validate: lambda { |choice| "Invalid selection:" unless (1..choices.size).cover?(choice) },
        transform: lambda { |choice| choices[choice - 1] },
        media: media
      )
    end

    def yes?(msg)
      select(msg, ["Yes", "No"]) == "Yes"
    end

    private

    def validate_media_choices_compatibility(media, choices)
      return unless media && choices

      if choices.length > 3
        raise ArgumentError, "Media with more than 3 choices is not supported. Please use either media OR choices for more than 3 options."
      end
    end

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

    def prompt!(msg, choices: nil, media: nil)
      raise FlowChat::Interrupt::Prompt.new(msg, choices: choices, media: media)
    end

    def terminate!(msg, media: nil)
      raise FlowChat::Interrupt::Terminate.new(msg, media: media)
    end
  end
end 
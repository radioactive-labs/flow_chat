module FlowChat
  class Prompt
    attr_reader :user_input

    def initialize(input)
      @user_input = input
    end

    def ask(msg, choices: nil, transform: nil, validate: nil, media: nil)
      if user_input.present?
        input = user_input
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

    def select(msg, choices, media: nil, error_message: "Invalid selection:")
      raise ArgumentError, "choices must be an array or hash" unless choices.is_a?(Array) || choices.is_a?(Hash)

      normalized_choices = normalize_choices(choices)
      ask(
        msg,
        choices: choices,
        validate: lambda { |choice| error_message unless normalized_choices.key?(choice.to_s) },
        transform: lambda do |choice|
          choices = choices.keys if choices.is_a?(Hash)
          choices.index_by { |choice| choice.to_s }[choice.to_s]
        end,
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

    def normalize_choices(choices)
      case choices
      when nil
        nil
      when Hash
        choices.map { |k, v| [k.to_s, v] }.to_h
      when Array
        choices.map { |c| [c.to_s, c] }.to_h
      else
        raise ArgumentError, "choices must be an array or hash"
      end
    end

    def prompt!(msg, choices: nil, media: nil)
      validate_media_choices_compatibility(media, choices)

      choices = normalize_choices(choices)
      raise FlowChat::Interrupt::Prompt.new(msg, choices: choices, media: media)
    end

    def terminate!(msg, media: nil)
      raise FlowChat::Interrupt::Terminate.new(msg, media: media)
    end
  end
end 
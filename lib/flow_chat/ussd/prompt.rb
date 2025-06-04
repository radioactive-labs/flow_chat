module FlowChat
  module Ussd
    class Prompt
      attr_reader :user_input

      def initialize(input)
        @user_input = input
      end

      def ask(msg, choices: nil, convert: nil, validate: nil, transform: nil, media: nil)
        if user_input.present?
          input = user_input
          input = convert.call(input) if convert.present?
          validation_error = validate.call(input) if validate.present?

          if validation_error.present?
            # Include media URL in validation error message
            original_message_with_media = build_message_with_media(msg, media)
            prompt!([validation_error, original_message_with_media].join("\n\n"), choices:)
          end

          input = transform.call(input) if transform.present?
          return input
        end

        # Include media URL in the message for USSD
        final_message = build_message_with_media(msg, media)
        prompt! final_message, choices:
      end

      def say(message, media: nil)
        # Include media URL in the message for USSD
        final_message = build_message_with_media(message, media)
        terminate! final_message
      end

      def select(msg, choices)
        choices, choices_prompt = build_select_choices choices
        ask(
          msg,
          choices: choices_prompt,
          convert: lambda { |choice| choice.to_i },
          validate: lambda { |choice| "Invalid selection:" unless (1..choices.size).cover?(choice) },
          transform: lambda { |choice| choices[choice - 1] }
        )
      end

      def yes?(msg)
        select(msg, ["Yes", "No"]) == "Yes"
      end

      private

      def build_message_with_media(message, media)
        return message unless media

        media_url = media[:url] || media[:path]
        media_type = media[:type] || :image

        # For USSD, we append the media URL to the message
        media_text = case media_type.to_sym
                    when :image
                      "📷 Image: #{media_url}"
                    when :document
                      "📄 Document: #{media_url}"
                    when :audio
                      "🎵 Audio: #{media_url}"
                    when :video
                      "🎥 Video: #{media_url}"
                    when :sticker
                      "😊 Sticker: #{media_url}"
                    else
                      "📎 Media: #{media_url}"
                    end

        # Combine message with media information
        "#{message}\n\n#{media_text}"
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

      def prompt!(msg, choices:)
        raise FlowChat::Interrupt::Prompt.new(msg, choices:)
      end

      def terminate!(msg)
        raise FlowChat::Interrupt::Terminate.new(msg)
      end
    end
  end
end

module FlowChat
  module Whatsapp
    class Prompt
      attr_reader :input

      def initialize(input)
        @input = input
      end

      def ask(message, transform: nil, validate: nil, convert: nil)
        if input.present?
          processed_input = process_input(input, transform, validate, convert)
          return processed_input unless processed_input.nil?
        end

        # Send message and wait for response
        raise FlowChat::Interrupt::Prompt.new([:text, message, {}])
      end

      def select(message, choices, transform: nil, validate: nil, convert: nil)
        if input.present?
          processed_input = process_selection(input, choices, transform, validate, convert)
          return processed_input unless processed_input.nil?
        end

        # Validate choices
        validate_choices(choices)

        # Determine the best way to present choices
        if choices.is_a?(Array)
          # Convert array to hash with index-based keys
          choice_hash = choices.each_with_index.to_h { |choice, index| [index.to_s, choice] }
          present_choices_as_list(message, choice_hash)
        elsif choices.is_a?(Hash)
          if choices.length <= 3
            # Use buttons for 3 or fewer choices
            present_choices_as_buttons(message, choices)
          else
            # Use list for more than 3 choices
            present_choices_as_list(message, choices)
          end
        else
          raise ArgumentError, "choices must be an Array or Hash"
        end
      end

      def yes?(message, transform: nil, validate: nil, convert: nil)
        if input.present?
          processed_input = process_boolean(input, transform, validate, convert)
          return processed_input unless processed_input.nil?
        end

        buttons = [
          { id: "yes", title: "Yes" },
          { id: "no", title: "No" }
        ]

        raise FlowChat::Interrupt::Prompt.new([:interactive_buttons, message, { buttons: buttons }])
      end

      private

      def process_input(input, transform, validate, convert)
        # Apply transformation
        transformed_input = transform ? transform.call(input) : input

        # Apply conversion first, then validation
        converted_input = convert ? convert.call(transformed_input) : transformed_input

        # Apply validation on converted value
        if validate
          error_message = validate.call(converted_input)
          if error_message
            raise FlowChat::Interrupt::Prompt.new([:text, error_message, {}])
          end
        end

        converted_input
      end

      def process_selection(input, choices, transform, validate, convert)
        choice_hash = choices.is_a?(Array) ? 
          choices.each_with_index.to_h { |choice, index| [index.to_s, choice] } : 
          choices

        # Check if input matches a valid choice
        if choice_hash.key?(input)
          selected_value = choice_hash[input]
          process_input(selected_value, transform, validate, convert)
        elsif choice_hash.value?(input)
          # Input matches a choice value directly
          process_input(input, transform, validate, convert)
        else
          # Invalid choice
          choice_list = choice_hash.map { |key, value| "#{key}: #{value}" }.join("\n")
          error_message = "Invalid choice. Please select one of:\n#{choice_list}"
          raise FlowChat::Interrupt::Prompt.new([:text, error_message, {}])
        end
      end

      def process_boolean(input, transform, validate, convert)
        boolean_value = case input.to_s.downcase
                       when "yes", "y", "1", "true"
                         true
                       when "no", "n", "0", "false"
                         false
                       else
                         nil
                       end

        if boolean_value.nil?
          raise FlowChat::Interrupt::Prompt.new([:text, "Please answer with Yes or No.", {}])
        end

        process_input(boolean_value, transform, validate, convert)
      end

      def present_choices_as_buttons(message, choices)
        buttons = choices.map do |key, value|
          {
            id: key.to_s,
            title: truncate_text(value.to_s, 20) # WhatsApp button titles have a 20 character limit
          }
        end

        raise FlowChat::Interrupt::Prompt.new([:interactive_buttons, message, { buttons: buttons }])
      end

      def present_choices_as_list(message, choices)
        items = choices.map do |key, value|
          original_text = value.to_s
          truncated_title = truncate_text(original_text, 24)
          
          # If title was truncated, put full text in description (up to 72 chars)
          description = if original_text.length > 24
                         truncate_text(original_text, 72)
                       else
                         nil
                       end
          
          {
            id: key.to_s,
            title: truncated_title,
            description: description
          }.compact
        end

        # If 10 or fewer items, use single section
        if items.length <= 10
          sections = [
            {
              title: "Options",
              rows: items
            }
          ]
        else
          # Paginate into multiple sections (max 10 items per section)
          sections = items.each_slice(10).with_index.map do |section_items, index|
            start_num = (index * 10) + 1
            end_num = start_num + section_items.length - 1
            
            {
              title: "#{start_num}-#{end_num}",
              rows: section_items
            }
          end
        end

        raise FlowChat::Interrupt::Prompt.new([:interactive_list, message, { sections: sections }])
      end

      def validate_choices(choices)
        # Check for empty choices
        if choices.nil? || choices.empty?
          raise ArgumentError, "choices cannot be empty"
        end

        choice_count = choices.is_a?(Array) ? choices.length : choices.length

        # WhatsApp supports max 100 total items across all sections
        if choice_count > 100
          raise ArgumentError, "WhatsApp supports maximum 100 choice options, got #{choice_count}"
        end

        # Validate individual choice values
        choices_to_validate = choices.is_a?(Array) ? choices : choices.values

        choices_to_validate.each_with_index do |choice, index|
          if choice.nil? || choice.to_s.strip.empty?
            raise ArgumentError, "choice at index #{index} cannot be empty"
          end

          choice_text = choice.to_s
          if choice_text.length > 100
            raise ArgumentError, "choice '#{choice_text[0..20]}...' is too long (#{choice_text.length} chars). Maximum is 100 characters"
          end
        end
      end

      def truncate_text(text, length)
        return text if text.length <= length
        text[0, length - 3] + "..."
      end
    end
  end
end 
module FlowChat
  module Meta
    # Which interactive surface renders a given number of choices.
    #
    # The renderer and the choice mapper both need this answer, and they must
    # agree: the renderer decides what the user sees, the mapper decides what a
    # reply is allowed to mean. Two copies of the arithmetic would drift into a
    # screen whose replies cannot be resolved.
    module ChoiceLadder
      def self.rung_for(count, limits)
        return :none if count.zero?
        return :quick_replies if count <= limits.max_quick_replies
        return :carousel if count <= carousel_capacity(limits)

        :numbered
      end

      # The carousel holds elements, each holding buttons, and one option is one
      # button.
      def self.carousel_capacity(limits)
        limits.max_carousel_elements * limits.max_buttons_per_element
      end

      # Whether the options are also listed, numbered, in the message body.
      #
      # always_number is for platforms whose interactive surfaces do not render
      # everywhere. Without it a user who cannot see the buttons has no way to
      # answer at all.
      def self.numbers_in_body?(count, limits, always_number: false)
        return false if count.zero?
        return true if always_number

        rung_for(count, limits) == :numbered
      end
    end
  end
end

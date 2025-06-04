module FlowChat
  module Interrupt
    # standard:disable Lint/InheritException
    class Base < Exception
      attr_reader :prompt

      def initialize(prompt)
        @prompt = prompt
        super
      end
    end
    # standard:enable Lint/InheritException

    class Prompt < Base
      attr_reader :choices

      def initialize(*args, choices: nil)
        @choices = choices
        super(*args)
      end
    end

    class Terminate < Base; end
  end
end

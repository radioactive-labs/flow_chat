module FlowChat
  module Interrupt
    class Base < Exception
      attr_reader :prompt

      def initialize(prompt)
        @prompt = prompt
        super
      end
    end

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

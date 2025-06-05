module FlowChat
  module Interrupt
    # standard:disable Lint/InheritException
    class Base < Exception
      attr_reader :prompt, :media

      def initialize(prompt, media: nil)
        @prompt = prompt
        @media = media
        super(prompt)
      end
    end
    # standard:enable Lint/InheritException

    class Prompt < Base
      attr_reader :choices

      def initialize(prompt, choices: nil, media: nil)
        @choices = choices
        super(prompt, media: media)
      end
    end

    class Terminate < Base; end
  end
end

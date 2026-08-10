module FlowChat
  module Instagram
    class Client < FlowChat::Messenger::Client
      private

      def renderer_class
        FlowChat::Instagram::Renderer
      end

      def platform
        :instagram
      end

      def limits
        FlowChat::Config.instagram
      end

      # Meta: "Message text must be UTF-8 and be 1,000 bytes or less." A
      # character count would let multibyte text through to be rejected.
      def measure(string)
        string.bytesize
      end

      # Meta's Instagram send reference documents recipient and message only,
      # with no messaging_type. Inheriting Messenger's would put an undocumented
      # parameter on every Instagram send.
      def messaging_type?
        false
      end
    end
  end
end

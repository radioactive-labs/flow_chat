module FlowChat
  module Instagram
    # Instagram's ladder is Messenger's algorithm with different constants.
    # The gateways are siblings (Instagram's does not depend on Messenger's),
    # but the renderers really are the same shape, so this is the one place
    # Instagram inherits from Messenger rather than mirroring it.
    class Renderer < FlowChat::Messenger::Renderer
      private

      def limits
        FlowChat::Config.instagram
      end

      # Quick replies and carousels are mobile only on Instagram, so the
      # options are always listed in the body as well. A user on desktop
      # sees the prompt and nothing tappable, and without the list has no
      # way to reply at all.
      def always_number?
        true
      end
    end
  end
end

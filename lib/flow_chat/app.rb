module FlowChat
  class App
    attr_reader :input, :context, :navigation_stack

    def initialize(context)
      @context = context
      @input = build_input
      @navigation_stack = []
    end

    def screen(key)
      raise ArgumentError, "a block is expected" unless block_given?
      raise ArgumentError, "screen has already been presented" if navigation_stack.include?(key)

      navigation_stack << key
      # A screen is answered once its key is stored — even when the stored value is
      # blank (a caption-less attachment yields ""). Guard on presence-in-session
      # (non-nil), not truthiness, so media-only (and false/blank) answers stick
      # instead of re-asking every turn.
      cached = session.get(key)
      return cached unless cached.nil?

      user_input = prepare_user_input
      prompt = FlowChat::Prompt.new user_input
      # The turn has been handed to a screen; later screens in this run must not
      # re-consume it. We mark it consumed rather than discarding it, so the
      # read accessors (text/media/...) stay available for the rest of the run.
      @input_consumed = true

      value = yield prompt
      session.set(key, value)
      value
    end

    def go_back
      return false if navigation_stack.empty?

      @input_consumed = true
      current_screen = navigation_stack.last
      session.delete(current_screen)

      # Restart the flow from the beginning
      raise FlowChat::Interrupt::RestartFlow.new
    end

    def say(msg, media: nil)
      raise FlowChat::Interrupt::Terminate.new(msg, media: media)
    end

    def platform
      context["request.platform"]
    end

    def gateway
      context["request.gateway"]
    end

    def user_id
      context["request.user_id"]
    end

    def msisdn
      context["request.msisdn"]
    end

    def message_id
      context["request.message_id"]
    end

    def timestamp
      context["request.timestamp"]
    end

    # The sender's display name — distinct from a contact card they may share
    # (that's #contact).
    def contact_name
      context["request.user_name"]
    end

    # Read accessors for the turn delegate to the Input value object, which is
    # the single source of truth for this turn's text and attachments.
    def text
      input.text
    end

    # Always an Array<FlowChat::Media> (empty when none) — a list even on
    # single-media platforms, so callers iterate uniformly.
    def media
      input.media
    end

    def location
      input.location
    end

    def contact
      input.contact
    end

    def attachment
      input.attachment
    end

    def attachment_type
      input.attachment_type
    end

    def session
      @context.session
    end

    protected

    # The turn as a FlowChat::Input value object. Its #present? accounts for
    # attachments, so a caption-less photo still answers a screen even though its
    # text is blank. Built once and kept for the whole run (see #screen).
    def build_input
      FlowChat::Input.new(
        text: context.input,
        media: wrap_media(context["request.media"]),
        location: context["request.location"],
        contact: context["request.contact"]
      )
    end

    def wrap_media(raw)
      return [] unless raw

      items = raw.is_a?(Array) ? raw : [raw]
      items.map { |data| FlowChat::Media.new(data, platform: platform, client: media_client) }
    end

    def prepare_user_input
      return nil if @input_consumed

      user_input = input
      if platform != :ussd && session.get(FlowChat::Input::START).nil?
        # First inbound message of the session. Mark it started (store the text, a
        # serializable string — not the Input object), then swallow a text-only
        # opener: the classic "wake the flow / show the first screen" behavior.
        # An opener that carries an attachment is let through so the first screen
        # can consume it rather than silently dropping the media/location/contact.
        session.set(FlowChat::Input::START, user_input.to_s)
        return nil unless user_input.attachment?
      end
      user_input
    end

    def media_client
      case platform
      when :whatsapp then context["whatsapp.client"]
      when :telegram then context["telegram.client"]
      when :intercom then context["intercom.client"]
      end
    end
  end
end

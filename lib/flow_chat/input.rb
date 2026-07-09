module FlowChat
  # A single inbound turn.
  #
  # Replaces the old "$media$"/"$location$"/"$contact$" sentinels: instead of
  # overloading the input string with a control signal, a turn carries its text
  # and (at most one) structured attachment as first-class fields.
  #
  # It behaves like its text wherever a string method is expected — so
  # validators/transforms written for text (`input.strip`, `input.to_i`,
  # `input.blank?`) keep working — while also exposing `#media`, `#location`,
  # `#contact`, and `#attachment_type` for the attachment. The prompt gates on
  # `#submitted?` (text OR attachment), so a caption-less photo still answers a
  # screen even though its text is blank.
  class Input
    # Session marker for the "first message" gate. Not a turn signal — kept as a
    # namespaced constant so `FlowChat::Input::START` continues to resolve.
    START = "$start$"

    # #media is always an Array<FlowChat::Media> (empty when none). It is a list
    # even on single-media platforms so callers iterate uniformly and never
    # silently drop the extra attachments a message can carry (e.g. Intercom).
    attr_reader :text, :media, :location, :contact

    def initialize(text: nil, media: nil, location: nil, contact: nil)
      @text = text.nil? ? "" : text.to_s
      @media = media || []
      @location = location
      @contact = contact
    end

    # Did the user send anything this turn — text OR an attachment? The prompt
    # gates on this so a caption-less photo answers a screen. Distinct from
    # #present?/#blank?, which follow the text (so text validators behave).
    def submitted?
      !@text.empty? || attachment?
    end

    def attachment?
      !attachment_type.nil?
    end

    # The structured payload on this turn — the media list, or the location /
    # contact hash — or nil. Pair with #attachment_type to know which.
    def attachment
      case attachment_type
      when :media then media
      when :location then location
      when :contact then contact
      end
    end

    # The kind of structured payload on this turn, or nil. At most one is ever
    # present in a single message, so this is a safe discriminator.
    def attachment_type
      return :media if @media.any?
      return :location if @location
      return :contact if @contact
      nil
    end

    def to_s
      @text
    end

    def ==(other)
      @text == other
    end

    # Behave like the text for any other PUBLIC string method (strip, to_i,
    # match?, length, empty?, ...), so text-oriented validators/transforms keep
    # working. Private String methods are not exposed — respond_to_missing? and
    # method_missing agree on public-only so `respond_to?` never lies.
    def respond_to_missing?(name, include_private = false)
      @text.respond_to?(name) || super
    end

    def method_missing(name, *args, &block)
      if @text.respond_to?(name)
        @text.send(name, *args, &block)
      else
        super
      end
    end
  end
end

module FlowChat
  # Shortens text to fit a display cap.
  #
  # Every renderer that fits a label into a platform's title limit needs this,
  # and so does every choice mapper that has to know exactly what the user is
  # looking at: a mapper that reimplemented the rule separately could drift
  # from what the renderer actually renders, silently reopening the bug this
  # class exists to prevent.
  module TextTruncator
    ELLIPSIS = "..."

    # length is clamped to zero or more before anything else: String#[] with
    # a negative second argument returns nil rather than raising, so a
    # negative length (reachable from #number below, whose prefix can eat
    # more than the whole cap at a small enough cap) would otherwise turn
    # `nil + "..."` into a NoMethodError deep inside a render.
    #
    # Below 3 there is no room left for the ellipsis itself - it alone is 3
    # characters - so a cap that small hard-truncates with no ellipsis
    # rather than returning something longer than the cap it was supposed to
    # respect.
    # measure picks the unit the cap is expressed in. :bytes exists because
    # Meta and Telegram both size these fields in bytes rather than
    # characters - FlowChat::Instagram::Client#measure already draws the same
    # distinction for message bodies, and for the same reason: a character
    # count lets multibyte text through to be rejected by the platform.
    def self.truncate(text, length, measure: :characters)
      text = text.to_s
      length = 0 if length.negative?
      return text if size_of(text, measure) <= length

      ellipsis = size_of(ELLIPSIS, measure)
      return cut(text, length, measure) if length < ellipsis

      cut(text, length - ellipsis, measure) + ELLIPSIS
    end

    # Prefixes text with its 1-based position on the rung ("1. ", "10. ",
    # "100. ") and truncates the label to make room, so the combined string
    # never exceeds cap. The prefix's length depends on position, so it has
    # to be computed per choice rather than once for the whole rung: choice
    # 10 loses one more character to its label than choice 1 does.
    #
    # Every renderer and choice mapper that numbers a choice's on-screen
    # title shares this, for the same reason .truncate is shared: a mapper
    # that reimplemented the prefix-and-truncate rule separately could drift
    # from what the renderer actually renders, silently reopening the bug
    # this class exists to prevent.
    def self.number(text, position, cap, measure: :characters)
      prefix = "#{position}. "
      prefix + truncate(text.to_s, cap - size_of(prefix, measure), measure: measure)
    end

    def self.size_of(string, measure)
      (measure == :bytes) ? string.bytesize : string.length
    end
    private_class_method :size_of

    # Takes whole characters while they still fit the budget. Slicing bytes
    # directly would cut a multi-byte sequence in half and hand the platform
    # a string that is no longer valid UTF-8.
    def self.cut(string, budget, measure)
      return "" if budget <= 0
      return string[0, budget] unless measure == :bytes

      taken = +""
      string.each_char do |char|
        break if taken.bytesize + char.bytesize > budget
        taken << char
      end
      taken
    end
    private_class_method :cut
  end
end

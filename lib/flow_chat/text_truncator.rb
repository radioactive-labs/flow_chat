module FlowChat
  # Shortens text to fit a display cap.
  #
  # Every renderer that fits a label into a platform's title limit needs this,
  # and so does every choice mapper that has to know exactly what the user is
  # looking at: a mapper that reimplemented the rule separately could drift
  # from what the renderer actually renders, silently reopening the bug this
  # class exists to prevent.
  module TextTruncator
    def self.truncate(text, length)
      return text if text.length <= length
      text[0, length - 3] + "..."
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
    def self.number(text, position, cap)
      prefix = "#{position}. "
      prefix + truncate(text.to_s, cap - prefix.length)
    end
  end
end

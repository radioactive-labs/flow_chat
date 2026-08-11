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
  end
end

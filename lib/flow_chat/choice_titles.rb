module FlowChat
  # Decides, once per choice set rather than once per choice, whether every
  # title in that set needs a 1-based position prefix ("1. ", "2. ", and so
  # on), then returns the on-screen title FlowChat will render for each
  # choice.
  #
  # The trigger is ambiguity, not truncation specifically: a screen is
  # ambiguous when, having computed each choice's title at the rung's cap,
  # either any title had to be truncated, or two choices land on the same
  # title. Both mean the titles as displayed cannot identify a choice on
  # their own:
  #
  # - Truncation can make two different labels ("Transfer to savings
  #   account" / "Transfer to salary account") land on the same displayed
  #   text ("Transfer to sa...").
  # - Two choices can share a label outright with no truncation involved at
  #   all (two accounts both nicknamed "Savings", a menu with two literal
  #   "Accept" options) - the keys behind them differ, but the titles a user
  #   would type back are identical.
  #
  # Numbering is decided for the whole set, never per choice: prefixing only
  # the affected title would produce "Yes" / "2. Transfer to savi...", a
  # stray number with no "1." next to it to make sense of.
  #
  # The renderer and every choice mapper share this one decision, for the
  # same reason FlowChat::TextTruncator is shared: two independent
  # reimplementations could disagree about which rung is ambiguous, and a
  # disagreement here means a title on screen that nothing resolves.
  module ChoiceTitles
    IDENTITY = ->(string) { string }

    # @param choices [Hash] original choice key => label, in the order the
    #   caller numbers positions in - the renderer and the mapper must
    #   enumerate the same choices in the same order, or the titles and
    #   aliases they compute will not match
    # @param cap [Integer] the rung's title length limit
    # @return [Array<[String, String, String, Boolean]>] one
    #   [key, original_label, displayed_title, label_was_truncated] tuple per
    #   choice, in the same order as `choices`
    # @param fold [Proc] the normalization the resolver applies to input
    #   before matching it. Two titles that fold to the same string cannot
    #   be told apart by that resolver, so the set is ambiguous and gets
    #   numbered. USSD is the one mapper that needs no fold: it resolves on
    #   position, which is injective by construction.
    # @param measure [Symbol] :characters or :bytes, whichever unit the
    #   platform sizes the field in
    def self.build(choices, cap, fold: IDENTITY, measure: :characters)
      reason = ambiguity_reason(choices, cap, fold: fold, measure: measure)
      prefixed = !reason.nil?

      if prefixed
        FlowChat.logger.debug { "#{name}: numbering choices, titles are ambiguous (#{reason})" }
      end

      choices.map.with_index(1) do |(key, label), position|
        label = label.to_s
        width = (measure == :bytes) ? label.bytesize : label.length

        if prefixed
          prefix = "#{position}. "
          prefix_width = (measure == :bytes) ? prefix.bytesize : prefix.length
          title = FlowChat::TextTruncator.number(label, position, cap, measure: measure)
          truncated = width > (cap - prefix_width)
        else
          title = FlowChat::TextTruncator.truncate(label, cap, measure: measure)
          truncated = width > cap
        end

        [key.to_s, label, title, truncated]
      end
    end

    # @return [Boolean] whether this choice set is ambiguous at this cap
    def self.ambiguous?(choices, cap, fold: IDENTITY, measure: :characters)
      !ambiguity_reason(choices, cap, fold: fold, measure: measure).nil?
    end

    # @return [String, nil] a description of why the set is ambiguous, for
    #   logging, or nil when it is not
    def self.ambiguity_reason(choices, cap, fold: IDENTITY, measure: :characters)
      labels = choices.map { |_, label| label.to_s }
      titles = labels.map { |label| FlowChat::TextTruncator.truncate(label, cap, measure: measure) }

      truncated_labels = labels.zip(titles).select { |label, title| title != label }.map(&:first)
      duplicate_titles = titles.map { |title| fold.call(title) }.tally.select { |_, count| count > 1 }.keys

      return nil if truncated_labels.empty? && duplicate_titles.empty?

      parts = []
      parts << "truncated: #{truncated_labels.inspect}" unless truncated_labels.empty?
      parts << "duplicate titles: #{duplicate_titles.inspect}" unless duplicate_titles.empty?
      parts.join(", ")
    end
  end
end

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
  #   "Accept" options) - IdGenerator still gives them distinct ids, but the
  #   titles a user would type back are identical.
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
    # @param choices [Hash] original choice key => label, in the order the
    #   caller numbers positions in - the renderer and the mapper must
    #   enumerate the same choices in the same order, or the titles and
    #   aliases they compute will not match
    # @param cap [Integer] the rung's title length limit
    # @return [Array<[String, String, String, Boolean]>] one
    #   [key, original_label, displayed_title, label_was_truncated] tuple per
    #   choice, in the same order as `choices`
    def self.build(choices, cap)
      reason = ambiguity_reason(choices, cap)
      prefixed = !reason.nil?

      if prefixed
        FlowChat.logger.debug { "#{name}: numbering choices, titles are ambiguous (#{reason})" }
      end

      choices.map.with_index(1) do |(key, label), position|
        label = label.to_s

        if prefixed
          title = FlowChat::TextTruncator.number(label, position, cap)
          truncated = label.length > (cap - "#{position}. ".length)
        else
          title = FlowChat::TextTruncator.truncate(label, cap)
          truncated = label.length > cap
        end

        [key.to_s, label, title, truncated]
      end
    end

    # @return [Boolean] whether this choice set is ambiguous at this cap
    def self.ambiguous?(choices, cap)
      !ambiguity_reason(choices, cap).nil?
    end

    # @return [String, nil] a description of why the set is ambiguous, for
    #   logging, or nil when it is not
    def self.ambiguity_reason(choices, cap)
      labels = choices.map { |_, label| label.to_s }
      titles = labels.map { |label| FlowChat::TextTruncator.truncate(label, cap) }

      truncated_labels = labels.zip(titles).select { |label, title| title != label }.map(&:first)
      duplicate_titles = titles.tally.select { |_, count| count > 1 }.keys

      return nil if truncated_labels.empty? && duplicate_titles.empty?

      parts = []
      parts << "truncated: #{truncated_labels.inspect}" unless truncated_labels.empty?
      parts << "duplicate titles: #{duplicate_titles.inspect}" unless duplicate_titles.empty?
      parts.join(", ")
    end

    # Builds the reply alias for each choice's on-screen title, so a user who
    # types exactly what they see resolves to the same choice as a user who
    # types the generated id or, when one is shown, the bare position number.
    #
    # Correctness here rests entirely on .build's own guarantee - that it
    # never hands back two identical titles for the same set - which is what
    # lets this skip any cross-choice collision check: there is nothing left
    # to collide.
    #
    # One guard remains, and it is reachable: on an unambiguous set (the
    # common case - short, distinct labels), the title is just the bare
    # label, which very often equals the choice's own generated id outright
    # ("Yes" the label, "Yes" the id). Registering that as an alias would be
    # redundant, not wrong - the id map already resolves it - so it is
    # skipped to keep the alias map free of pointless duplicate entries.
    #
    # @param choices [Hash] original choice key => label, as the flow wrote
    #   it, enumerated in the same order .build numbers positions in
    # @param generated_ids [Hash] choice key (String) => id from IdGenerator
    # @param display_cap [Integer, nil] the renderer's title length for the
    #   rung these choices landed on, or nil when the rung has no separate
    #   title to alias (it numbers the message body directly instead)
    # @return [Hash] displayed title => choice key
    def self.aliases_for(choices, generated_ids, display_cap)
      return {} unless display_cap

      build(choices, display_cap).each_with_object({}) do |(key, _label, title, _truncated), aliases|
        next if title == generated_ids.fetch(key)
        aliases[title] = key
      end
    end
  end
end

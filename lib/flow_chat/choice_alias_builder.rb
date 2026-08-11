module FlowChat
  # Builds the reply alias for each choice's on-screen title, so a user who
  # types exactly what they see resolves to the same choice as a user who
  # types the generated id or, when one is shown, the bare position number.
  #
  # The titles themselves come from FlowChat::ChoiceTitles, which decides
  # once per choice set whether the titles need a position prefix to stay
  # distinct. That guarantee - that FlowChat::ChoiceTitles never hands back
  # two identical titles for the same set - is what lets this module skip
  # any cross-choice collision check: there is nothing left to collide.
  #
  # One guard remains, and it is reachable: on an unambiguous set (the
  # common case - short, distinct labels), the title is just the bare
  # label, which very often equals the choice's own generated id outright
  # ("Yes" the label, "Yes" the id). Registering that as an alias would be
  # redundant, not wrong - the id map already resolves it - so it is
  # skipped to keep the alias map free of pointless duplicate entries.
  module ChoiceAliasBuilder
    # @param choices [Hash] original choice key => label, as the flow wrote
    #   it, enumerated in the same order FlowChat::ChoiceTitles and the
    #   renderer number them in
    # @param generated_ids [Hash] choice key (String) => id from IdGenerator
    # @param display_cap [Integer, nil] the renderer's title length for the
    #   rung these choices landed on, or nil when the rung has no separate
    #   title to alias (it numbers the message body directly instead)
    # @return [Hash] displayed title => choice key
    def self.build(choices, generated_ids, display_cap)
      return {} unless display_cap

      FlowChat::ChoiceTitles.build(choices, display_cap).each_with_object({}) do |(key, _label, title, _truncated), aliases|
        next if title == generated_ids.fetch(key)
        aliases[title] = key
      end
    end
  end
end

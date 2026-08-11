module FlowChat
  # Builds the reply alias for each choice's on-screen, possibly truncated,
  # label, so a user who types exactly what they see resolves to the same
  # choice as a user who types the untruncated generated id.
  #
  # An alias is registered only when it is safe:
  # - it must differ from the choice's own generated id, or it is pointless
  #   (that id already resolves the choice);
  # - it must not collide with any choice's generated id, or with another
  #   choice's truncated label.
  #
  # A collision is worse than a miss. Dropping the alias just means a typed
  # reply does not match and the flow re-prompts, which is recoverable;
  # resolving it to the wrong choice is not.
  module ChoiceAliasBuilder
    # @param choices [Hash] original choice key => label, as the flow wrote it
    # @param generated_ids [Hash] choice key (String) => id from IdGenerator
    # @param display_cap [Integer, nil] the renderer's title length for the
    #   rung these choices landed on, or nil when the rung shows the full
    #   label (no truncation, so no alias is needed)
    # @return [Hash] displayed label => choice key, for labels safe to alias
    def self.build(choices, generated_ids, display_cap)
      return {} unless display_cap

      candidates = Hash.new { |h, k| h[k] = [] }

      choices.each do |key, label|
        key = key.to_s
        generated_id = generated_ids.fetch(key)
        truncated = FlowChat::TextTruncator.truncate(label.to_s, display_cap)
        next if truncated == generated_id

        candidates[truncated] << key
      end

      candidates.each_with_object({}) do |(truncated, keys), aliases|
        next if keys.length > 1 # ambiguous: two choices display the same truncated text
        next if generated_ids.value?(truncated) # collides with a generated id already in play

        aliases[truncated] = keys.first
      end
    end
  end
end

require "digest"

module FlowChat
  # Generates platform-safe IDs from choice labels
  #
  # Interactive replies are identified by an id rather than by the label the
  # user saw, and every platform caps that id differently: WhatsApp list rows
  # at 256 characters, Messenger quick-reply payloads at 1000. The cap is a
  # constructor argument so one generator serves all of them.
  #
  # This generator:
  # - Sanitizes labels to alphanumeric + underscore/hyphen
  # - Truncates to fit within the configured limit
  # - Appends hash suffix for duplicate labels (similar to Rails index naming)
  # - Ensures readability while maintaining uniqueness
  #
  # @example Basic usage
  #   generator = IdGenerator.new
  #   id = generator.generate_id("Create Account")  # => "create_account"
  #
  # @example Handling duplicates
  #   generator = IdGenerator.new
  #   id1 = generator.generate_id("Accept")  # => "accept"
  #   id2 = generator.generate_id("Accept")  # => "accept_a1b2c3"
  #
  # @example Special characters
  #   generator = IdGenerator.new
  #   id = generator.generate_id("Yes! 👍 (recommended)")  # => "yes_recommended"
  #
  # @example A platform with a different cap
  #   generator = IdGenerator.new(max_length: 1000)
  #
  class IdGenerator
    DEFAULT_MAX_ID_LENGTH = 256
    HASH_SUFFIX_LENGTH = 3

    attr_reader :max_length

    def initialize(max_length: DEFAULT_MAX_ID_LENGTH)
      @max_length = max_length
      @generated_ids = []
    end

    # Generate a platform-safe ID from a label
    #
    # @param label [String] The choice label to convert
    # @return [String] A sanitized, unique ID
    def generate_id(label)
      # Normalize the label
      normalized = normalize_label(label)

      # If normalized label is empty, use a fallback
      normalized = "choice" if normalized.empty?

      # Truncate to limit first
      truncated = truncate_to_limit(normalized)

      # Check if we need a hash suffix for uniqueness
      final_id = if @generated_ids.include?(truncated)
        add_hash_suffix(truncated, label)
      else
        truncated
      end

      # Track this ID
      @generated_ids << final_id

      final_id
    end

    # Reset the generator state (useful for testing or starting a new message)
    def reset
      @generated_ids = []
    end

    # Get all generated IDs (useful for debugging)
    def generated_ids
      @generated_ids.dup
    end

    private

    # Normalize a label into a platform-safe identifier
    # Keeps readability by preserving spaces and basic punctuation
    #
    # @param label [String] The original label
    # @return [String] Normalized identifier
    def normalize_label(label)
      label
        .to_s
        .gsub(/[^\w\s\-']/, "")        # remove special chars (keep word chars, spaces, hyphens, apostrophes)
        .gsub(/\s+/, " ")              # collapse multiple spaces to single space (after removing chars)
        .strip                          # trim leading/trailing whitespace
    end

    # Add a hash suffix to make the ID unique
    #
    # The hash is generated from the original label to ensure
    # the same label always produces the same hash.
    #
    # @param base_id [String] The base identifier
    # @param original_label [String] The original label for hash generation
    # @return [String] ID with hash suffix
    def add_hash_suffix(base_id, original_label)
      # Generate a short hash from the original label + timestamp for uniqueness
      # We use the current generated_ids count to ensure different duplicates get different hashes
      hash_input = "#{original_label}_#{@generated_ids.count { |id| id.start_with?(base_id) }}"
      hash = Digest::SHA256.hexdigest(hash_input)[0...HASH_SUFFIX_LENGTH]

      # Calculate max base length to fit: base + "_" + hash, within this generator's cap
      max_base_length = max_length - HASH_SUFFIX_LENGTH - 1

      # Truncate base if needed
      truncated_base = base_id[0...max_base_length]

      "#{truncated_base} #{hash}"
    end

    # Truncate ID to maximum allowed length
    #
    # @param id [String] The ID to truncate
    # @return [String] Truncated ID
    def truncate_to_limit(id)
      return id if id.length <= max_length
      id[0...max_length]
    end
  end
end

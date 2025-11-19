require "test_helper"

module FlowChat
  module Whatsapp
    class IdGeneratorTest < Minitest::Test
      def setup
        @generator = IdGenerator.new
      end

      def test_basic_id_generation
        id = @generator.generate_id("Create Account")
        assert_equal "Create Account", id
      end

      def test_lowercase_conversion
        # No longer converting to lowercase - preserving original case for readability
        id = @generator.generate_id("LOGIN USER")
        assert_equal "LOGIN USER", id
      end

      def test_space_to_underscore
        # Spaces are preserved for readability
        id = @generator.generate_id("Sign Up Now")
        assert_equal "Sign Up Now", id
      end

      def test_special_characters_removed
        # Only removes incompatible special chars, keeps spaces
        id = @generator.generate_id("Yes! (recommended)")
        assert_equal "Yes recommended", id
      end

      def test_emoji_removed
        id = @generator.generate_id("🔥 Hot Deal")
        assert_equal "Hot Deal", id
      end

      def test_multiple_spaces_collapsed
        # Multiple spaces collapsed to single space
        id = @generator.generate_id("Accept    Terms")
        assert_equal "Accept Terms", id
      end

      def test_leading_trailing_spaces_removed
        id = @generator.generate_id("  Account  ")
        assert_equal "Account", id
      end

      def test_hyphens_preserved
        id = @generator.generate_id("Sign-In")
        assert_equal "Sign-In", id
      end

      def test_underscores_preserved
        id = @generator.generate_id("user_login")
        assert_equal "user_login", id
      end

      def test_alphanumeric_preserved
        # Spaces preserved
        id = @generator.generate_id("Option 123")
        assert_equal "Option 123", id
      end

      def test_duplicate_labels_get_unique_ids
        id1 = @generator.generate_id("Accept")
        id2 = @generator.generate_id("Accept")

        assert_equal "Accept", id1
        refute_equal id1, id2
        # Hash suffix uses space separator and 3-char hash
        assert_match /^Accept\s[a-f0-9]{3}$/, id2
      end

      def test_multiple_duplicates_all_unique
        ids = 5.times.map { @generator.generate_id("Same Label") }

        assert_equal "Same Label", ids[0]
        assert_equal 5, ids.uniq.length, "All IDs should be unique"

        ids[1..4].each do |id|
          # Hash suffix uses space separator and 3-char hash
          assert_match /^Same Label\s[a-f0-9]{3}$/, id
        end
      end

      def test_empty_string_uses_fallback
        id = @generator.generate_id("")
        assert_equal "choice", id
      end

      def test_whitespace_only_uses_fallback
        id = @generator.generate_id("   ")
        assert_equal "choice", id
      end

      def test_special_chars_only_uses_fallback
        id = @generator.generate_id("!@#$%")
        assert_equal "choice", id
      end

      def test_id_within_256_char_limit
        long_label = "a" * 500
        id = @generator.generate_id(long_label)

        assert id.length <= IdGenerator::MAX_ID_LENGTH
      end

      def test_duplicate_long_label_within_limit
        long_label = "This is an extremely long choice label " * 10
        id1 = @generator.generate_id(long_label)
        id2 = @generator.generate_id(long_label)

        assert id1.length <= IdGenerator::MAX_ID_LENGTH
        assert id2.length <= IdGenerator::MAX_ID_LENGTH
        refute_equal id1, id2
      end

      def test_hash_suffix_is_deterministic_for_position
        # Reset and generate first duplicate
        @generator.reset
        @generator.generate_id("Test")
        id1 = @generator.generate_id("Test")

        # Reset and generate first duplicate again
        @generator.reset
        @generator.generate_id("Test")
        id2 = @generator.generate_id("Test")

        assert_equal id1, id2, "Same duplicate position should generate same hash"
      end

      def test_reset_clears_state
        @generator.generate_id("Accept")
        id_before_reset = @generator.generate_id("Accept")

        @generator.reset
        id_after_reset = @generator.generate_id("Accept")

        assert_equal "Accept", id_after_reset
        refute_equal id_before_reset, id_after_reset
      end

      def test_generated_ids_returns_copy
        @generator.generate_id("Test 1")
        @generator.generate_id("Test 2")

        ids = @generator.generated_ids
        ids << "manipulated"

        assert_equal 2, @generator.generated_ids.length
      end

      def test_unicode_characters_removed
        id = @generator.generate_id("Café Münchën")
        assert_equal "Caf Mnchn", id
      end

      def test_consecutive_special_chars_collapsed
        id = @generator.generate_id("Hello!!!World")
        assert_equal "HelloWorld", id
      end

      def test_mixed_special_chars_and_spaces
        id = @generator.generate_id("Sign-Up & Login!")
        assert_equal "Sign-Up Login", id
      end

      def test_already_normalized_labels_unchanged
        id = @generator.generate_id("already_normalized_id")
        assert_equal "already_normalized_id", id
      end

      def test_numeric_labels
        id = @generator.generate_id("123")
        assert_equal "123", id
      end

      def test_real_world_labels
        test_cases = {
          "Create new account" => "Create new account",
          "Log in" => "Log in",
          "Reset password" => "Reset password",
          "Continue as guest" => "Continue as guest",
          "I agree to terms & conditions" => "I agree to terms conditions",
          "Next →" => "Next",
          "← Back" => "Back",
          "✓ Confirm" => "Confirm",
          "✗ Cancel" => "Cancel"
        }

        test_cases.each do |label, expected_id|
          @generator.reset
          id = @generator.generate_id(label)
          assert_equal expected_id, id, "Label: '#{label}'"
        end
      end

      def test_max_length_without_hash_suffix
        # Create a label that's exactly at the limit when normalized
        label = "a" * IdGenerator::MAX_ID_LENGTH
        id = @generator.generate_id(label)

        assert_equal IdGenerator::MAX_ID_LENGTH, id.length
        assert_equal "a" * IdGenerator::MAX_ID_LENGTH, id
      end

      def test_max_length_with_hash_suffix
        # Create a duplicate that needs hash suffix
        long_label = "a" * IdGenerator::MAX_ID_LENGTH
        @generator.generate_id(long_label)
        id_with_hash = @generator.generate_id(long_label)

        assert id_with_hash.length <= IdGenerator::MAX_ID_LENGTH
        # Hash suffix uses space separator and 3-char hash
        assert_match /\s[a-f0-9]{3}$/, id_with_hash
      end

      def test_different_labels_produce_different_ids
        labels = [
          "Create Account",
          "Delete Account",
          "View Account",
          "Edit Account"
        ]

        ids = labels.map { |label| @generator.generate_id(label) }

        assert_equal ids.uniq.length, ids.length, "All different labels should produce different IDs"
      end

      def test_case_sensitive_different_ids
        # IDs are now case-preserving, so different cases are different IDs
        id1 = @generator.generate_id("Accept")
        id2 = @generator.generate_id("ACCEPT")
        id3 = @generator.generate_id("accept")

        assert_equal "Accept", id1
        assert_equal "ACCEPT", id2
        assert_equal "accept", id3
        # All three are different (case-sensitive)
        refute_equal id1, id2
        refute_equal id2, id3
        refute_equal id1, id3
      end
    end
  end
end

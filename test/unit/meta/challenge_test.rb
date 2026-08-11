require "test_helper"

class MetaChallengeTest < Minitest::Test
  TOKEN = "our-verify-token"

  def params(token, challenge = "nonce-123")
    {"hub.mode" => "subscribe", "hub.verify_token" => token, "hub.challenge" => challenge}
  end

  def test_answers_with_the_challenge_when_the_token_matches
    assert_equal "nonce-123", FlowChat::Meta::Challenge.answer(params(TOKEN), TOKEN)
  end

  def test_refuses_a_token_that_does_not_match
    assert_nil FlowChat::Meta::Challenge.answer(params("not-ours"), TOKEN)
  end

  def test_refuses_a_request_carrying_no_token
    assert_nil FlowChat::Meta::Challenge.answer(params(nil), TOKEN)
  end

  # Without the presence check a missing token on both sides compares equal, and
  # the endpoint answers to anyone who asks.
  def test_refuses_everything_when_no_token_is_configured
    assert_nil FlowChat::Meta::Challenge.answer(params(""), "")
    assert_nil FlowChat::Meta::Challenge.answer(params(nil), nil)
    assert_nil FlowChat::Meta::Challenge.answer(params("   "), "   ")
  end

  # The challenge is echoed as it arrived, whatever it is.
  def test_echoes_the_challenge_it_was_given
    assert_equal "0", FlowChat::Meta::Challenge.answer(params(TOKEN, "0"), TOKEN)
  end
end

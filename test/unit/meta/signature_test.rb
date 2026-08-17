require "test_helper"

class MetaSignatureTest < Minitest::Test
  SECRET = "app-secret"
  BODY = '{"object":"whatsapp_business_account"}'

  def signed(body, secret = SECRET)
    "sha256=" + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), secret, body)
  end

  def test_accepts_a_body_signed_with_the_secret
    assert FlowChat::Meta::Signature.valid?(BODY, signed(BODY), SECRET)
  end

  def test_accepts_a_header_without_the_prefix
    bare = signed(BODY).delete_prefix("sha256=")

    assert FlowChat::Meta::Signature.valid?(BODY, bare, SECRET)
  end

  def test_rejects_a_body_that_changed_after_signing
    refute FlowChat::Meta::Signature.valid?(BODY + " ", signed(BODY), SECRET)
  end

  def test_rejects_a_signature_from_another_secret
    refute FlowChat::Meta::Signature.valid?(BODY, signed(BODY, "someone-elses"), SECRET)
  end

  def test_rejects_a_missing_signature
    refute FlowChat::Meta::Signature.valid?(BODY, nil, SECRET)
    refute FlowChat::Meta::Signature.valid?(BODY, "", SECRET)
  end

  # Total rather than raising: a caller holding no secret is asking this
  # question, and the answer is no.
  def test_rejects_everything_when_there_is_no_secret_to_check_against
    refute FlowChat::Meta::Signature.valid?(BODY, signed(BODY), nil)
    refute FlowChat::Meta::Signature.valid?(BODY, signed(BODY), "")
    refute FlowChat::Meta::Signature.valid?(BODY, signed(BODY), "   ")
  end

  # A blank secret must not become a secret anyone can guess: signing with ""
  # and offering that signature is exactly the attack the check above stops.
  def test_a_signature_computed_from_a_blank_secret_is_not_accepted
    refute FlowChat::Meta::Signature.valid?(BODY, signed(BODY, ""), "")
  end
end

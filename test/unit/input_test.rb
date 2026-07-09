require "test_helper"

class InputTest < Minitest::Test
  def test_text_defaults_to_empty_string
    assert_equal "", FlowChat::Input.new.text
    assert_equal "", FlowChat::Input.new(text: nil).text
  end

  def test_text_is_coerced_to_string
    assert_equal "hello", FlowChat::Input.new(text: "hello").text
  end

  def test_submitted_when_text_is_given
    assert FlowChat::Input.new(text: "hi").submitted?
    refute FlowChat::Input.new(text: "").submitted?
    refute FlowChat::Input.new.submitted?
  end

  def test_submitted_when_attachment_is_given_even_without_text
    assert FlowChat::Input.new(media: [{type: :image}]).submitted?
    assert FlowChat::Input.new(location: {latitude: 1}).submitted?
    assert FlowChat::Input.new(contact: {name: "Jane"}).submitted?
  end

  def test_attachment_type_discriminates
    assert_equal :media, FlowChat::Input.new(media: [{type: :image}]).attachment_type
    assert_equal :location, FlowChat::Input.new(location: {}).attachment_type
    assert_equal :contact, FlowChat::Input.new(contact: {}).attachment_type
    assert_nil FlowChat::Input.new(text: "hi").attachment_type
  end

  def test_media_is_always_a_list
    input = FlowChat::Input.new(media: [:a, :b])
    assert_equal [:a, :b], input.media
    assert_equal [], FlowChat::Input.new.media
  end

  def test_attachment_returns_the_payload
    # media → the list; location/contact → their hash
    assert_equal [:img], FlowChat::Input.new(media: [:img]).attachment
    loc = {latitude: 1}
    assert_equal loc, FlowChat::Input.new(location: loc).attachment
    contact = {name: "Jane"}
    assert_equal contact, FlowChat::Input.new(contact: contact).attachment
    assert_nil FlowChat::Input.new(text: "hi").attachment
  end

  def test_behaves_like_its_text_for_string_methods
    input = FlowChat::Input.new(text: "  John Doe  ")
    assert_equal "John Doe", input.strip
    assert_equal 8, input.strip.length
    assert_equal "42", FlowChat::Input.new(text: "42").to_s
    assert_equal 42, FlowChat::Input.new(text: "42").to_i
    assert FlowChat::Input.new(text: "hello").match?(/ell/)
  end

  def test_present_and_blank_follow_the_text_not_the_attachment
    # So text validators (`input.blank?`) behave, even on a media turn.
    media_only = FlowChat::Input.new(media: [{type: :image}])
    assert media_only.blank?
    refute media_only.present?
    assert FlowChat::Input.new(text: "hi").present?
  end

  def test_respond_to_and_call_agree_public_only
    input = FlowChat::Input.new(text: "hi")
    # A public String method is delegated and advertised.
    assert input.respond_to?(:upcase)
    assert_equal "HI", input.upcase
    # An unknown method is neither advertised nor callable (no lying).
    refute input.respond_to?(:definitely_not_a_method, true)
    assert_raises(NoMethodError) { input.definitely_not_a_method }
  end

  def test_equality_compares_against_text
    assert_equal FlowChat::Input.new(text: "yes"), "yes"
    assert FlowChat::Input.new(text: "yes") == "yes"
  end

  def test_to_s_is_the_text
    assert_equal "hello", FlowChat::Input.new(text: "hello").to_s
    assert_equal "", FlowChat::Input.new.to_s
  end

  def test_start_marker_constant_is_retained
    assert_equal "$start$", FlowChat::Input::START
  end
end

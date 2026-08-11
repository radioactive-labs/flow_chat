require "test_helper"

class MessengerRendererTest < Minitest::Test
  def render(message, choices: nil, media: nil)
    FlowChat::Messenger::Renderer.new(message, choices: choices, media: media).render
  end

  def test_plain_text_message
    result = render("Hello **world**")

    assert_equal :text, result[0]
    assert_equal "Hello world", result[1]
    assert_equal({}, result[2])
  end

  def test_quick_replies_for_thirteen_or_fewer
    choices = (1..13).to_h { |i| ["k#{i}", "Option #{i}"] }

    result = render("Pick one", choices: choices)

    assert_equal :quick_replies, result[0]
    assert_equal 13, result[2][:quick_replies].length
    assert_equal "text", result[2][:quick_replies][0][:content_type]
    # These titles are short and distinct, so FlowChat::ChoiceTitles does
    # not prefix them.
    assert_equal "Option 1", result[2][:quick_replies][0][:title]
    assert_equal "k1", result[2][:quick_replies][0][:payload]
  end

  # Two choices sharing a label is ambiguous with no truncation involved at
  # all, and it is the case that exercises position coming from enumeration
  # order rather than from the choice key: "z" is enumerated first, so it
  # gets "1.", even though "a" would sort first by key.
  def test_quick_reply_titles_are_numbered_by_position_not_by_key
    choices = {"z" => "Accept", "a" => "Accept"}

    result = render("Pick", choices: choices)

    assert_equal "1. Accept", result[2][:quick_replies][0][:title]
    assert_equal "2. Accept", result[2][:quick_replies][1][:title]
  end

  def test_quick_reply_titles_truncate_at_twenty
    result = render("Pick", choices: {"k" => "A title that is definitely longer than twenty"})

    assert_equal 20, result[2][:quick_replies][0][:title].length
    assert_equal "1. A title that i...", result[2][:quick_replies][0][:title]
  end

  def test_carousel_between_fourteen_and_thirty
    choices = (1..14).to_h { |i| ["k#{i}", "Option #{i}"] }

    result = render("Pick one", choices: choices)

    assert_equal :carousel, result[0]
    assert_equal 5, result[2][:elements].length
    assert_equal 3, result[2][:elements][0][:buttons].length
    assert_equal "postback", result[2][:elements][0][:buttons][0][:type]
    assert_equal "k1", result[2][:elements][0][:buttons][0][:payload]
    # These titles are short and distinct, so FlowChat::ChoiceTitles does
    # not prefix them.
    assert_equal "Option 1", result[2][:elements][0][:buttons][0][:title]
  end

  # Two choices can share a label without either being truncated, and they
  # can do it across elements: the 1st and 14th options are in different
  # elements (the 1st and 5th), so nothing within either element's own
  # slice looks duplicated. FlowChat::ChoiceTitles.build runs on the whole
  # `choices` hash before build_carousel slices it, so this is still caught
  # and the whole set gets numbered - if the ambiguity check instead ran
  # per slice, this collision would be invisible and neither title would be
  # aliasable.
  def test_carousel_ambiguity_is_detected_across_element_slices
    choices = {"first" => "Foo"}.merge((2..13).to_h { |i| ["k#{i}", "Option #{i}"] }).merge("last" => "Foo")

    result = render("Pick one", choices: choices)

    first_element = result[2][:elements].first
    last_element = result[2][:elements].last

    assert_equal "1. Foo", first_element[:buttons].first[:title]
    # Position numbers the option across the whole choice set, not within
    # its element: the 14th option is the 2nd button of the 5th element,
    # and it must still read "14.", continuing from the 13th option in the
    # element before it, not restarting at "2." within its own element.
    assert_equal "14. Foo", last_element[:buttons].last[:title]
  end

  def test_carousel_never_exceeds_ten_elements
    choices = (1..30).to_h { |i| ["k#{i}", "Option #{i}"] }

    result = render("Pick one", choices: choices)

    assert_equal :carousel, result[0]
    assert_equal 10, result[2][:elements].length
    assert_equal 30, result[2][:elements].sum { |e| e[:buttons].length }
  end

  def test_numbered_body_above_thirty
    choices = (1..31).to_h { |i| ["k#{i}", "Option #{i}"] }

    result = render("Pick one", choices: choices)

    assert_equal :text, result[0]
    assert_includes result[1], "1. Option 1"
    assert_includes result[1], "31. Option 31"
  end

  def test_attachment_without_choices
    result = render("A caption", media: {type: :image, url: "https://example.com/a.png"})

    assert_equal :attachment, result[0]
    assert_equal "A caption", result[1]
    assert_equal :image, result[2][:type]
    assert_equal "https://example.com/a.png", result[2][:url]
  end

  # Media is additive: it rides along on whichever rung the choice count
  # would render anyway, rather than changing the choice surface.

  def test_media_with_a_small_choice_set_still_renders_quick_replies
    choices = {"a" => "Alpha", "b" => "Beta"}
    media = {type: :image, url: "https://example.com/a.png"}

    result = render("Pick one", choices: choices, media: media)

    assert_equal :quick_replies, result[0]
    assert_equal 2, result[2][:quick_replies].length
    assert_equal({type: :image, url: "https://example.com/a.png"}, result[2][:media])
  end

  def test_media_with_a_mid_size_choice_set_still_renders_a_carousel
    choices = (1..14).to_h { |i| ["k#{i}", "Option #{i}"] }
    media = {type: :image, url: "https://example.com/a.png"}

    result = render("Pick one", choices: choices, media: media)

    assert_equal :carousel, result[0]
    assert_equal 5, result[2][:elements].length
    assert_equal({type: :image, url: "https://example.com/a.png"}, result[2][:media])
  end

  def test_media_above_the_carousel_cap_still_renders_numbered_text
    choices = (1..31).to_h { |i| ["k#{i}", "Option #{i}"] }
    media = {type: :image, url: "https://example.com/a.png"}

    result = render("Pick one", choices: choices, media: media)

    assert_equal :text, result[0]
    assert_includes result[1], "31. Option 31"
    assert_equal({type: :image, url: "https://example.com/a.png"}, result[2][:media])
  end

  def test_media_with_an_attachment_id_instead_of_url
    result = render("Pick one", choices: {"a" => "Alpha"}, media: {type: :image, id: "att_1"})

    assert_equal({type: :image, attachment_id: "att_1"}, result[2][:media])
  end
end

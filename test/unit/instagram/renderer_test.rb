require "test_helper"

class InstagramRendererTest < Minitest::Test
  def render(message, choices: nil, media: nil)
    FlowChat::Instagram::Renderer.new(message, choices: choices, media: media).render
  end

  # Quick replies render on mobile Instagram only. Without numbers in the
  # body a user on desktop gets a prompt with nothing tappable and no way to
  # answer it at all.
  def test_quick_replies_also_number_the_body
    result = render("Pick one", choices: {"a" => "Alpha", "b" => "Beta"})

    assert_equal :quick_replies, result[0]
    assert_includes result[1], "1. Alpha"
    assert_includes result[1], "2. Beta"
  end

  # always_number? only ever controls the body listing tested above; it
  # says nothing about whether a title itself is prefixed. These titles are
  # short and distinct, so the quick reply's own title is not prefixed even
  # though the body right next to it always is - the two are independent
  # mechanisms answering different questions (can a desktop user, with no
  # tappable surface, still see the options? vs. can these titles identify
  # a choice on their own?).
  def test_quick_reply_titles_are_not_numbered_when_unambiguous
    result = render("Pick one", choices: {"a" => "Alpha", "b" => "Beta"})

    assert_equal "Alpha", result[2][:quick_replies][0][:title]
    assert_equal "Beta", result[2][:quick_replies][1][:title]
  end

  # Contrast with the above: an ambiguous set (two choices sharing a label)
  # does get its quick-reply titles prefixed too, on top of the numbered
  # body Instagram always shows.
  def test_quick_reply_titles_are_numbered_when_ambiguous
    result = render("Pick one", choices: {"a" => "Accept", "b" => "Accept"})

    assert_equal "1. Accept", result[2][:quick_replies][0][:title]
    assert_equal "2. Accept", result[2][:quick_replies][1][:title]
  end

  # The literal shape the plan's acceptance criteria call out: a five-choice
  # screen must carry both the tappable quick replies and the numbered list.
  def test_five_choices_carries_quick_replies_and_a_numbered_body
    choices = (1..5).to_h { |i| ["k#{i}", "Option #{i}"] }

    result = render("Pick one", choices: choices)

    assert_equal :quick_replies, result[0]
    assert_equal 5, result[2][:quick_replies].length
    (1..5).each { |i| assert_includes result[1], "#{i}. Option #{i}" }
  end

  def test_carousel_also_numbers_the_body
    choices = (1..14).to_h { |i| ["k#{i}", "Option #{i}"] }

    result = render("Pick one", choices: choices)

    assert_equal :carousel, result[0]
    assert_includes result[1], "14. Option 14"
  end

  def test_no_choices_means_no_numbers
    result = render("Just a message")

    assert_equal "Just a message", result[1]
  end
end

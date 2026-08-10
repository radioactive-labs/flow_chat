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
    assert_equal "Option 1", result[2][:quick_replies][0][:title]
    assert_equal "k1", result[2][:quick_replies][0][:payload]
  end

  def test_quick_reply_titles_truncate_at_twenty
    result = render("Pick", choices: {"k" => "A title that is definitely longer than twenty"})

    assert_equal 20, result[2][:quick_replies][0][:title].length
  end

  def test_carousel_between_fourteen_and_thirty
    choices = (1..14).to_h { |i| ["k#{i}", "Option #{i}"] }

    result = render("Pick one", choices: choices)

    assert_equal :carousel, result[0]
    assert_equal 5, result[2][:elements].length
    assert_equal 3, result[2][:elements][0][:buttons].length
    assert_equal "postback", result[2][:elements][0][:buttons][0][:type]
    assert_equal "k1", result[2][:elements][0][:buttons][0][:payload]
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
end

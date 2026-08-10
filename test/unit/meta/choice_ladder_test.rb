require "test_helper"

class ChoiceLadderTest < Minitest::Test
  def setup
    @limits = FlowChat::Config.messenger
  end

  def test_no_choices
    assert_equal :none, FlowChat::Meta::ChoiceLadder.rung_for(0, @limits)
  end

  def test_quick_replies_up_to_thirteen
    assert_equal :quick_replies, FlowChat::Meta::ChoiceLadder.rung_for(1, @limits)
    assert_equal :quick_replies, FlowChat::Meta::ChoiceLadder.rung_for(13, @limits)
  end

  def test_carousel_between_fourteen_and_thirty
    assert_equal :carousel, FlowChat::Meta::ChoiceLadder.rung_for(14, @limits)
    assert_equal :carousel, FlowChat::Meta::ChoiceLadder.rung_for(30, @limits)
  end

  def test_numbered_above_the_carousel_capacity
    assert_equal :numbered, FlowChat::Meta::ChoiceLadder.rung_for(31, @limits)
    assert_equal :numbered, FlowChat::Meta::ChoiceLadder.rung_for(200, @limits)
  end

  def test_carousel_capacity_is_elements_times_buttons
    assert_equal 30, FlowChat::Meta::ChoiceLadder.carousel_capacity(@limits)
  end

  def test_numbers_in_body_on_the_numbered_rung
    assert FlowChat::Meta::ChoiceLadder.numbers_in_body?(31, @limits)
    refute FlowChat::Meta::ChoiceLadder.numbers_in_body?(5, @limits)
  end

  # Instagram renders quick replies and carousels on mobile only, so its
  # renderer numbers the body at every rung.
  def test_always_number_covers_every_rung
    assert FlowChat::Meta::ChoiceLadder.numbers_in_body?(5, @limits, always_number: true)
    assert FlowChat::Meta::ChoiceLadder.numbers_in_body?(20, @limits, always_number: true)
    refute FlowChat::Meta::ChoiceLadder.numbers_in_body?(0, @limits, always_number: true)
  end
end

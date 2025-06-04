require "test_helper"

class FlowChatTest < Minitest::Test
  def test_has_version_number
    refute_nil FlowChat::VERSION
    assert_match(/\A\d+\.\d+\.\d+\z/, FlowChat::VERSION)
  end

  def test_root_returns_pathname
    assert_respond_to FlowChat, :root
    assert_kind_of Pathname, FlowChat.root
    assert FlowChat.root.to_s.end_with?("lib")
  end
end 
require "test_helper"

class FlowTest < Minitest::Test
  def setup
    @mock_app = OpenStruct.new
    @flow = FlowChat::Flow.new(@mock_app)
  end

  def test_initializes_with_app
    assert_equal @mock_app, @flow.app
  end

  def test_app_is_accessible
    assert_respond_to @flow, :app
  end

  def test_inheritance_works
    custom_flow_class = Class.new(FlowChat::Flow) do
      def custom_method
        "test"
      end
    end

    custom_flow = custom_flow_class.new(@mock_app)
    assert_respond_to custom_flow, :custom_method
    assert_equal "test", custom_flow.custom_method
    assert_equal @mock_app, custom_flow.app
  end
end 
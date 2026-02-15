require "test_helper"

class FlowChat::Telegram::Middleware::ChoiceMapperTest < Minitest::Test
  def setup
    @app = Minitest::Mock.new
    @middleware = FlowChat::Telegram::Middleware::ChoiceMapper.new(@app)
    @context = create_test_context
  end

  def teardown
    @app.verify
  end

  def test_passes_through_when_no_session
    @context.instance_variable_set(:@session, nil)
    @context.input = "some_input"

    @app.expect(:call, [:text, "Response", nil, nil], [@context])

    result = @middleware.call(@context)

    assert_equal [:text, "Response", nil, nil], result
  end

  def test_passes_through_when_no_input
    @context.input = nil

    @app.expect(:call, [:text, "Response", nil, nil], [@context])

    result = @middleware.call(@context)

    assert_equal [:text, "Response", nil, nil], result
  end

  def test_passes_through_when_empty_input
    @context.input = ""

    @app.expect(:call, [:text, "Response", nil, nil], [@context])

    result = @middleware.call(@context)

    assert_equal [:text, "Response", nil, nil], result
  end

  def test_validates_callback_data_against_stored_choices
    # Store choices in session
    @context.session.set("telegram_choices", {"opt1" => "Option 1", "opt2" => "Option 2"})
    @context.input = "opt1"

    @app.expect(:call, [:text, "Response", nil, nil], [@context])

    result = @middleware.call(@context)

    # Input should pass through since it's a valid choice key
    assert_equal "opt1", @context.input
  end

  def test_stores_choices_in_session_after_response
    @context.input = "some text"
    choices = {"a" => "Choice A", "b" => "Choice B"}

    @app.expect(:call, [:text, "Pick:", choices, nil], [@context])

    @middleware.call(@context)

    # Verify choices were stored in session
    stored = @context.session.get("telegram_choices")
    assert_equal choices, stored
  end

  def test_does_not_store_nil_choices
    @context.input = "text"

    @app.expect(:call, [:text, "Response", nil, nil], [@context])

    @middleware.call(@context)

    stored = @context.session.get("telegram_choices")
    assert_nil stored
  end

  def test_does_not_store_non_hash_choices
    @context.input = "text"

    # This shouldn't happen in practice, but test defensive behavior
    @app.expect(:call, [:text, "Response", "not_a_hash", nil], [@context])

    @middleware.call(@context)

    stored = @context.session.get("telegram_choices")
    assert_nil stored
  end

  def test_updates_stored_choices_on_each_response
    # First response stores initial choices
    @context.input = "first"
    first_choices = {"x" => "X", "y" => "Y"}
    @app.expect(:call, [:text, "Pick:", first_choices, nil], [@context])
    @middleware.call(@context)

    assert_equal first_choices, @context.session.get("telegram_choices")

    # Second response updates choices
    @context.input = "second"
    second_choices = {"a" => "A", "b" => "B", "c" => "C"}
    @app.expect(:call, [:text, "Pick again:", second_choices, nil], [@context])
    @middleware.call(@context)

    assert_equal second_choices, @context.session.get("telegram_choices")
  end

  def test_handles_response_with_media_and_choices
    @context.input = "text"
    choices = {"like" => "Like", "share" => "Share"}
    media = {type: :photo, url: "https://example.com/photo.jpg"}

    @app.expect(:call, [:photo, "Caption", choices, media], [@context])

    @middleware.call(@context)

    stored = @context.session.get("telegram_choices")
    assert_equal choices, stored
  end

  def test_preserves_response_from_app
    @context.input = "hello"
    expected_response = [:text, "World", {"a" => "A"}, nil]

    @app.expect(:call, expected_response, [@context])

    result = @middleware.call(@context)

    assert_equal expected_response, result
  end

  def test_handles_nil_response_from_app
    @context.input = "hello"

    @app.expect(:call, nil, [@context])

    result = @middleware.call(@context)

    assert_nil result
  end

  private

  def create_test_context
    context = FlowChat::Context.new

    # Create a simple session mock
    session = Object.new
    session.instance_variable_set(:@data, {})

    def session.get(key)
      @data[key.to_s]
    end

    def session.set(key, value)
      @data[key.to_s] = value
    end

    context.instance_variable_set(:@session, session)
    def context.session
      @session
    end

    context
  end
end

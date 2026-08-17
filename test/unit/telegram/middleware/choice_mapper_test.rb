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

  # A tap sends the title as its callback_data, so the map turns it back
  # into the key the flow branches on. The old mapper never rewrote input at
  # all - it only logged - and relied on callback_data being the raw key.
  def test_resolves_a_tapped_title_back_to_its_key
    choices = {"opt1" => "Option 1", "opt2" => "Option 2"}
    @app.expect(:call, [:text, "Pick:", choices, nil], [@context])
    @middleware.call(@context)

    @context.input = "Option 2"
    @app.expect(:call, [:text, "Response", nil, nil], [@context])
    @middleware.call(@context)

    assert_equal "opt2", @context.input
  end

  def test_resolves_a_typed_position
    choices = {"opt1" => "Option 1", "opt2" => "Option 2"}
    @app.expect(:call, [:text, "Pick:", choices, nil], [@context])
    @middleware.call(@context)

    @context.input = "2"
    @app.expect(:call, [:text, "Response", nil, nil], [@context])
    @middleware.call(@context)

    assert_equal "opt2", @context.input
  end

  # callback_data is 1-64 *bytes*. Sizing it in characters let a multibyte
  # label through to be rejected by the API.
  def test_wire_values_fit_the_byte_limit_for_multibyte_labels
    long = "\u65e5\u672c\u8a9e\u306e\u30c6\u30ad\u30b9\u30c8\u3067\u3059 " * 6
    @app.expect(:call, [:text, "Pick:", {"a" => long, "b" => "#{long}!"}, nil], [@context])

    rendered = @middleware.call(@context)[2]

    rendered.keys.each do |wire_value|
      assert_operator wire_value.bytesize, :<=, FlowChat::Telegram::Middleware::ChoiceMapper::CALLBACK_DATA_LIMIT
      assert wire_value.valid_encoding?, "byte truncation must not split a character"
    end
  end

  # Two labels sharing a long prefix used to be cut to the same
  # callback_data, which then matched neither key - the choice could not be
  # picked at all. Numbering keeps them apart because the prefix survives a
  # cut from the right.
  def test_labels_sharing_a_long_prefix_stay_distinct_and_both_resolve
    shared = "Transfer to the account ending in " * 3
    choices = {"a" => "#{shared} one", "b" => "#{shared} two"}
    @app.expect(:call, [:text, "Pick:", choices, nil], [@context])
    wire_values = @middleware.call(@context)[2].keys

    assert_equal wire_values.length, wire_values.uniq.length, "callback_data must stay distinct"

    @context.input = wire_values[1]
    @app.expect(:call, [:text, "Response", nil, nil], [@context])
    @middleware.call(@context)

    assert_equal "b", @context.input
  end

  def test_stores_a_mapping_after_a_response_with_choices
    @context.input = "some text"
    choices = {"a" => "Choice A", "b" => "Choice B"}

    @app.expect(:call, [:text, "Pick:", choices, nil], [@context])

    @middleware.call(@context)

    assert_equal({"Choice A" => "a", "Choice B" => "b"},
      @context.session.get(FlowChat::Telegram::Middleware::ChoiceMapper::SESSION_KEY))
  end

  def test_does_not_store_nil_choices
    @context.input = "text"

    @app.expect(:call, [:text, "Response", nil, nil], [@context])

    @middleware.call(@context)

    assert_nil @context.session.get(FlowChat::Telegram::Middleware::ChoiceMapper::SESSION_KEY)
  end

  def test_does_not_store_non_hash_choices
    @context.input = "text"

    @app.expect(:call, [:text, "Response", "not_a_hash", nil], [@context])

    @middleware.call(@context)

    assert_nil @context.session.get(FlowChat::Telegram::Middleware::ChoiceMapper::SESSION_KEY)
  end

  def test_updates_the_mapping_on_each_response
    @context.input = "first"
    @app.expect(:call, [:text, "Pick:", {"x" => "X", "y" => "Y"}, nil], [@context])
    @middleware.call(@context)

    assert_equal({"X" => "x", "Y" => "y"},
      @context.session.get(FlowChat::Telegram::Middleware::ChoiceMapper::SESSION_KEY))

    @context.input = "second"
    @app.expect(:call, [:text, "Pick again:", {"a" => "A", "b" => "B"}, nil], [@context])
    @middleware.call(@context)

    assert_equal({"A" => "a", "B" => "b"},
      @context.session.get(FlowChat::Telegram::Middleware::ChoiceMapper::SESSION_KEY))
  end

  def test_handles_response_with_media_and_choices
    @context.input = "text"
    media = {type: :photo, url: "https://example.com/photo.jpg"}

    @app.expect(:call, [:photo, "Caption", {"like" => "Like", "share" => "Share"}, media], [@context])

    result = @middleware.call(@context)

    assert_equal({"Like" => "Like", "Share" => "Share"}, result[2])
    assert_equal media, result[3]
  end

  def test_preserves_response_from_app
    @context.input = "hello"
    @app.expect(:call, [:text, "World", {"a" => "A"}, nil], [@context])

    result = @middleware.call(@context)

    assert_equal :text, result[0]
    assert_equal "World", result[1]
    assert_equal({"A" => "A"}, result[2])
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

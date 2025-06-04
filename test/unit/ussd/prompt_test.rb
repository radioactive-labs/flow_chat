require "test_helper"

class UssdPromptTest < Minitest::Test
  def test_ask_with_no_input_raises_prompt_interrupt
    prompt = FlowChat::Ussd::Prompt.new(nil)
    
    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt.ask("What is your name?")
    end
    
    assert_equal "What is your name?", error.prompt
  end

  def test_ask_with_input_returns_input
    prompt = FlowChat::Ussd::Prompt.new("John")
    
    result = prompt.ask("What is your name?")
    assert_equal "John", result
  end

  def test_ask_with_convert_transforms_input
    prompt = FlowChat::Ussd::Prompt.new("25")
    
    result = prompt.ask("What is your age?", convert: ->(input) { input.to_i })
    assert_equal 25, result
    assert_kind_of Integer, result
  end

  def test_ask_with_validation_fails
    prompt = FlowChat::Ussd::Prompt.new("12")
    
    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt.ask("What is your age?", 
        convert: ->(input) { input.to_i },
        validate: ->(input) { "Must be at least 18" unless input >= 18 }
      )
    end
    
    assert_includes error.prompt, "Must be at least 18"
    assert_includes error.prompt, "What is your age?"
  end

  def test_ask_with_validation_passes
    prompt = FlowChat::Ussd::Prompt.new("25")
    
    result = prompt.ask("What is your age?",
      convert: ->(input) { input.to_i },
      validate: ->(input) { "Must be at least 18" unless input >= 18 }
    )
    
    assert_equal 25, result
  end

  def test_ask_with_transform_modifies_valid_input
    prompt = FlowChat::Ussd::Prompt.new("  john doe  ")
    
    result = prompt.ask("What is your name?", transform: ->(input) { input.strip.titleize })
    assert_equal "John Doe", result
  end

  def test_select_with_array_choices
    prompt = FlowChat::Ussd::Prompt.new("2")
    
    result = prompt.select("Choose gender", ["Male", "Female"])
    assert_equal "Female", result
  end

  def test_select_with_hash_choices
    prompt = FlowChat::Ussd::Prompt.new("1")
    choices = { "m" => "Male", "f" => "Female" }
    
    result = prompt.select("Choose gender", choices)
    assert_equal "m", result
  end

  def test_select_with_invalid_choice
    prompt = FlowChat::Ussd::Prompt.new("5")
    
    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt.select("Choose gender", ["Male", "Female"])
    end
    
    assert_includes error.prompt, "Invalid selection"
  end

  def test_select_with_no_input_shows_choices
    prompt = FlowChat::Ussd::Prompt.new(nil)
    
    error = assert_raises(FlowChat::Interrupt::Prompt) do
      prompt.select("Choose gender", ["Male", "Female"])
    end
    
    assert_includes error.prompt, "Choose gender"
    expected_choices = {1 => "Male", 2 => "Female"}
    assert_equal expected_choices, error.choices
  end

  def test_yes_question_with_yes_answer
    prompt = FlowChat::Ussd::Prompt.new("1")  # "Yes" is first option
    
    result = prompt.yes?("Do you agree?")
    assert_equal true, result
  end

  def test_yes_question_with_no_answer
    prompt = FlowChat::Ussd::Prompt.new("2")  # "No" is second option
    
    result = prompt.yes?("Do you agree?")
    assert_equal false, result
  end

  def test_say_raises_terminate_interrupt
    prompt = FlowChat::Ussd::Prompt.new(nil)
    
    error = assert_raises(FlowChat::Interrupt::Terminate) do
      prompt.say("Thank you!")
    end
    
    assert_equal "Thank you!", error.prompt
  end

  def test_build_select_choices_with_array
    prompt = FlowChat::Ussd::Prompt.new(nil)
    choices = ["Option A", "Option B", "Option C"]
    
    result_choices, choices_prompt = prompt.send(:build_select_choices, choices)
    
    assert_equal choices, result_choices
    assert_equal({1 => "Option A", 2 => "Option B", 3 => "Option C"}, choices_prompt)
  end

  def test_build_select_choices_with_hash
    prompt = FlowChat::Ussd::Prompt.new(nil)
    choices = {"a" => "Option A", "b" => "Option B"}
    
    result_choices, choices_prompt = prompt.send(:build_select_choices, choices)
    
    assert_equal ["a", "b"], result_choices
    assert_equal({1 => "Option A", 2 => "Option B"}, choices_prompt)
  end

  def test_build_select_choices_with_invalid_type
    prompt = FlowChat::Ussd::Prompt.new(nil)
    
    assert_raises(ArgumentError) do
      prompt.send(:build_select_choices, "invalid")
    end
  end
end 
require "test_helper"

class InterruptTest < Minitest::Test
  def test_base_interrupt_stores_prompt
    prompt = "Test prompt"
    interrupt = FlowChat::Interrupt::Base.new(prompt)

    assert_equal prompt, interrupt.prompt
    assert_kind_of Exception, interrupt
  end

  def test_prompt_interrupt_stores_choices
    prompt = "Choose an option"
    choices = {1 => "Option 1", 2 => "Option 2"}
    interrupt = FlowChat::Interrupt::Prompt.new(prompt, choices: choices)

    assert_equal prompt, interrupt.prompt
    assert_equal choices, interrupt.choices
    assert_kind_of FlowChat::Interrupt::Base, interrupt
  end

  def test_prompt_interrupt_without_choices
    prompt = "Enter your name"
    interrupt = FlowChat::Interrupt::Prompt.new(prompt)

    assert_equal prompt, interrupt.prompt
    assert_nil interrupt.choices
  end

  def test_terminate_interrupt
    message = "Thank you!"
    interrupt = FlowChat::Interrupt::Terminate.new(message)

    assert_equal message, interrupt.prompt
    assert_kind_of FlowChat::Interrupt::Base, interrupt
  end

  def test_interrupts_are_exceptions
    assert_raises(FlowChat::Interrupt::Base) do
      raise FlowChat::Interrupt::Base.new("test")
    end

    assert_raises(FlowChat::Interrupt::Prompt) do
      raise FlowChat::Interrupt::Prompt.new("test")
    end

    assert_raises(FlowChat::Interrupt::Terminate) do
      raise FlowChat::Interrupt::Terminate.new("test")
    end
  end
end

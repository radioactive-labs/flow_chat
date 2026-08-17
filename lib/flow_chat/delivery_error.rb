module FlowChat
  # A reply the flow produced that the platform would not take.
  #
  # Raised by nothing: it exists so that a send which failed quietly, by
  # answering nil rather than raising, still reaches on_delivery_failure and
  # MESSAGE_DELIVERY_FAILED carrying something that names what happened. A
  # subscriber written against a raising client sees the same shape either way.
  class DeliveryError < StandardError; end
end

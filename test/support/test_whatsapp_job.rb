# Reusable test job for WhatsApp testing
class TestWhatsappJob < BaseTestJob
  include FlowChat::Whatsapp::SendJobSupport
  
  attr_accessor :success_callbacks, :error_callbacks
  
  def initialize
    @success_callbacks = []
    @error_callbacks = []
  end
  
  def perform(send_data)
    perform_whatsapp_send(send_data)
  end
  
  private
  
  def on_whatsapp_send_success(send_data, result)
    @success_callbacks << { send_data: send_data, result: result }
  end
  
  def on_whatsapp_send_error(error, send_data)
    @error_callbacks << { error: error, send_data: send_data }
  end
end 
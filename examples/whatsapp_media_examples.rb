# WhatsApp Media Examples
# Demonstrates sending and receiving media with FlowChat's WhatsApp integration.

# Sending media directly with the WhatsApp client, out of band.
config = FlowChat::Whatsapp::Configuration.from_credentials
client = FlowChat::Whatsapp::Client.new(config)

client.send_image("+1234567890", "https://example.com/image.jpg", "Caption")
client.send_document("+1234567890", "https://example.com/doc.pdf", "Document title", "filename.pdf")
client.send_audio("+1234567890", "https://example.com/audio.mp3")
client.send_video("+1234567890", "https://example.com/video.mp4", "Video caption")
client.send_sticker("+1234567890", "https://example.com/sticker.webp")

# Sending and receiving media inside a flow.
class MediaFlow < FlowChat::Flow
  def main_page
    # app.media is always an Array<FlowChat::Media> (empty when the turn carried
    # no attachment), so branch on whether it has any items.
    if app.media.any?
      handle_user_media
      return
    end

    # Attach media to a prompt.
    app.screen(:feedback) do |prompt|
      prompt.ask "What do you think?",
        media: {type: :image, url: "https://example.com/product.jpg"}
    end

    # Attach media to a terminal message.
    app.say "Thanks for your feedback!",
      media: {type: :video, url: "https://example.com/response.mp4"}
  end

  private

  def handle_user_media
    # Each item is a FlowChat::Media; item.type is a normalized Symbol
    # (:image, :video, :audio, :document, :sticker).
    media = app.media.first

    case media.type
    when :image
      app.say "Thanks for the image! Processing..."
    when :document
      app.say "Document received. Reviewing..."
    when :audio
      app.say "Got your voice message!"
    when :video
      app.say "Video received. Analyzing..."
    else
      app.say "Attachment received."
    end
  end
end

# An out-of-band service for sending media outside a conversation, for example
# from a background job or another controller.
class MediaService
  def initialize
    @client = FlowChat::Whatsapp::Client.new(FlowChat::Whatsapp::Configuration.from_credentials)
  end

  def send_welcome_package(phone_number, user_name)
    @client.send_image(phone_number, "https://cdn.example.com/welcome.jpg", "Welcome #{user_name}!")
    @client.send_document(phone_number, "https://storage.example.com/guide.pdf", "User Guide")
  end

  def send_order_confirmation(phone_number, order_id, invoice_url)
    @client.send_document(phone_number, invoice_url, "Order ##{order_id} confirmed", "invoice.pdf")
    @client.send_buttons(phone_number, "Order confirmed", [
      {id: "track", title: "Track Order"},
      {id: "support", title: "Contact Support"}
    ])
  end
end

# Controller that sends media notifications on demand.
class NotificationController < ApplicationController
  def send_media_notification
    MediaService.new.send_welcome_package(params[:phone], params[:name])
    render json: {status: "sent"}
  end
end

# WhatsApp Media Examples
# This file demonstrates media usage with FlowChat's WhatsApp integration

# Basic media sending with WhatsApp Client
config = FlowChat::Whatsapp::Configuration.from_credentials
client = FlowChat::Whatsapp::Client.new(config)

# Send different media types
client.send_image("+1234567890", "https://example.com/image.jpg", "Caption")
client.send_document("+1234567890", "https://example.com/doc.pdf", "Document title", "filename.pdf")
client.send_audio("+1234567890", "https://example.com/audio.mp3")
client.send_video("+1234567890", "https://example.com/video.mp4", "Video caption")
client.send_sticker("+1234567890", "https://example.com/sticker.webp")

# Using media in flows
class MediaFlow < FlowChat::Flow
  def main_page
    # Handle incoming media
    if app.media
      handle_user_media
      return
    end

    # Send media with prompts
    app.screen(:feedback) do |prompt|
      prompt.ask "What do you think?",
        media: {
          type: :image,
          url: "https://example.com/product.jpg"
        }
    end

    # Send media responses
    app.say "Thanks for your feedback!",
      media: {
        type: :video,
        url: "https://example.com/response.mp4"
      }
  end

  private

  def handle_user_media
    media_type = app.media["type"]

    case media_type
    when "image"
      app.say "Thanks for the image! Processing..."
    when "document"
      app.say "Document received. Reviewing..."
    when "audio"
      app.say "Got your voice message!"
    when "video"
      app.say "Video received. Analyzing..."
    end
  end
end

# Media service for out-of-band messaging
class MediaService
  def initialize
    @config = FlowChat::Whatsapp::Configuration.from_credentials
    @client = FlowChat::Whatsapp::Client.new(@config)
  end

  def send_welcome_package(phone_number, user_name)
    @client.send_image(phone_number, "https://cdn.example.com/welcome.jpg", "Welcome #{user_name}!")
    @client.send_document(phone_number, "https://storage.example.com/guide.pdf", "User Guide")
  end

  def send_order_confirmation(phone_number, order_id, invoice_url)
    @client.send_document(phone_number, invoice_url, "Order ##{order_id} confirmed!", "invoice.pdf")
    @client.send_buttons(phone_number, "Order confirmed! 🛍️", [
      {id: "track", title: "Track Order"},
      {id: "support", title: "Contact Support"}
    ])
  end

  def process_user_media(media_id, media_type, user_phone)
    # Download and process media
    @client.get_media_url(media_id)
    media_content = @client.download_media(media_id)

    # Process based on type
    case media_type
    when "image"
      process_image(media_content, user_phone)
    when "document"
      process_document(media_content, user_phone)
    when "audio"
      process_audio(media_content, user_phone)
    end
  end

  private

  def process_image(content, phone)
    # Your image processing logic
    @client.send_text(phone, "Image processed successfully! ✅")
  end

  def process_document(content, phone)
    # Your document processing logic
    @client.send_text(phone, "Document processed! 📄")
  end

  def process_audio(content, phone)
    # Your audio processing logic
    @client.send_text(phone, "Audio processed! 🎵")
  end
end

# Controller example for media notifications
class NotificationController < ApplicationController
  def send_media_notification
    service = MediaService.new
    service.send_welcome_package(params[:phone], params[:name])
    render json: {status: "sent"}
  end

  def send_order_confirmation
    service = MediaService.new
    service.send_order_confirmation(
      params[:phone],
      params[:order_id],
      generate_invoice_url(params[:order_id])
    )
    render json: {status: "sent"}
  end

  private

  def generate_invoice_url(order_id)
    "https://storage.example.com/invoices/#{order_id}.pdf"
  end
end

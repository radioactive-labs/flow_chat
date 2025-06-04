# WhatsApp Media Messaging Examples
# This file demonstrates how to send different types of media via WhatsApp using FlowChat

# ============================================================================
# BASIC MEDIA SENDING (Out-of-Band Messaging)
# ============================================================================

# Initialize the WhatsApp client
config = FlowChat::Whatsapp::Configuration.from_credentials
client = FlowChat::Whatsapp::Client.new(config)

# Send an image from URL with caption
client.send_image("+1234567890", "https://example.com/images/product.jpg", "Check out this amazing photo!")

# Send a document from URL
client.send_document("+1234567890", "https://example.com/reports/monthly_report.pdf", "Here's the monthly report")

# Send an audio file from URL
client.send_audio("+1234567890", "https://example.com/audio/greeting.mp3")

# Send a video from URL with caption
client.send_video("+1234567890", "https://example.com/videos/demo.mp4", "Product demo video")

# Send a sticker from URL
client.send_sticker("+1234567890", "https://example.com/stickers/happy.webp")

# You can also still use existing WhatsApp media IDs
client.send_image("+1234567890", "1234567890", "Image from existing media ID")

# ============================================================================
# USING MEDIA IN FLOWS
# ============================================================================

class MediaSupportFlow < FlowChat::Flow
  def main_page
    # Handle incoming media from user
    if app.media
      handle_received_media
      return
    end

    choice = app.screen(:main_menu) do |prompt|
      prompt.select "Welcome! How can I help you?", {
        "catalog" => "📷 View Product Catalog",
        "report" => "📄 Get Report",
        "support" => "🎵 Voice Support",
        "feedback" => "📝 Send Feedback"
      }
    end

    case choice
    when "catalog"
      send_product_catalog
    when "report"
      send_report
    when "support"
      send_voice_message
    when "feedback"
      collect_feedback
    end
  end

  private

  def handle_received_media
    media_type = app.media['type']
    media_id = app.media['id']
    
    Rails.logger.info "Received #{media_type} from #{app.phone_number}: #{media_id}"
    
    case media_type
    when 'image'
      app.say "Thanks for the image! I can see it's a #{media_type} file. Let me process it for you."
    when 'document'
      app.say "I've received your document. I'll review it and get back to you shortly."
    when 'audio'
      app.say "Got your voice message! I'll listen to it and respond appropriately."
    when 'video'
      app.say "Thanks for the video! I'll analyze it and provide feedback."
    end
  end

  def send_product_catalog
    # Send multiple product images from URLs
    client = get_whatsapp_client
    
    app.say "Here's our latest product catalog:"
    
    # Product images stored in cloud storage (CDN, S3, etc.)
    product_images = [
      "https://cdn.example.com/products/product1.jpg",
      "https://cdn.example.com/products/product2.jpg", 
      "https://cdn.example.com/products/product3.jpg"
    ]
    
    product_images.each_with_index do |image_url, index|
      client.send_image(app.phone_number, image_url, "Product #{index + 1}")
      sleep(0.5) # Small delay to avoid rate limiting
    end
    
    app.say "Which product interests you the most?"
  end

  def send_report
    # Send a PDF report from cloud storage
    report_url = generate_report_url # Your method to generate/get report URL
    
    if report_url
      client = get_whatsapp_client
      client.send_document(app.phone_number, report_url, "Your monthly report is ready!")
      
      app.say "📊 Report sent! Please check the document above."
    else
      app.say "Sorry, I couldn't generate the report right now. Please try again later."
    end
  end

  def send_voice_message
    # Send a pre-recorded voice message from cloud storage
    audio_url = "https://cdn.example.com/audio/support_greeting.mp3"
    
    client = get_whatsapp_client
    client.send_audio(app.phone_number, audio_url)
    
    app.say "🎵 Please listen to the voice message above. You can also send me a voice message with your question!"
  end

  def collect_feedback
    feedback = app.screen(:feedback_text) do |prompt|
      prompt.ask "Please share your feedback. You can also send images or documents if needed:"
    end
    
    # Save feedback to database
    save_feedback(feedback, app.phone_number)
    
    # Send a thank you sticker from cloud storage
    sticker_url = "https://cdn.example.com/stickers/thanks.webp"
    client = get_whatsapp_client
    client.send_sticker(app.phone_number, sticker_url)
    
    app.say "Thank you for your feedback! We really appreciate it. 🙏"
  end

  def get_whatsapp_client
    config = FlowChat::Whatsapp::Configuration.from_credentials
    FlowChat::Whatsapp::Client.new(config)
  end

  def generate_report_url
    # Your report generation logic here
    # This could return a signed URL from S3, Google Cloud Storage, etc.
    "https://storage.example.com/reports/monthly_report_#{Time.current.strftime('%Y%m')}.pdf"
  end

  def save_feedback(feedback, phone_number)
    # Your feedback saving logic here
    Rails.logger.info "Feedback from #{phone_number}: #{feedback}"
  end
end

# ============================================================================
# ADVANCED MEDIA SERVICE CLASS
# ============================================================================

class WhatsAppMediaService
  def initialize
    @config = FlowChat::Whatsapp::Configuration.from_credentials
    @client = FlowChat::Whatsapp::Client.new(@config)
  end

  # Send welcome package with multiple media types from URLs
  def send_welcome_package(phone_number, user_name)
    # Welcome image from CDN
    welcome_image_url = "https://cdn.example.com/welcome/banner.jpg"
    @client.send_image(phone_number, welcome_image_url, "Welcome to our service, #{user_name}! 🎉")

    # Welcome guide document from cloud storage
    guide_url = "https://storage.example.com/guides/user_guide.pdf"
    @client.send_document(phone_number, guide_url, "Here's your user guide")

    # Welcome audio message from media server
    audio_url = "https://media.example.com/audio/welcome.mp3"
    @client.send_audio(phone_number, audio_url)
  end

  # Send order confirmation with invoice from cloud storage
  def send_order_confirmation(phone_number, order_id, invoice_url)
    # Send invoice document from cloud storage
    @client.send_document(
      phone_number, 
      invoice_url, 
      "Order ##{order_id} confirmed! Here's your invoice.",
      "Invoice_#{order_id}.pdf"
    )

    # Send confirmation buttons
    @client.send_buttons(
      phone_number,
      "Your order has been confirmed! 🛍️",
      [
        { id: 'track_order', title: '📦 Track Order' },
        { id: 'modify_order', title: '✏️ Modify Order' },
        { id: 'support', title: '💬 Contact Support' }
      ]
    )
  end

  # Send promotional content from CDN
  def send_promotion(phone_number, promo_image_url, promo_video_url = nil)
    # Send promotional image from CDN
    @client.send_image(phone_number, promo_image_url, "🔥 Special offer just for you!")

    # Optionally send promotional video from video server
    if promo_video_url
      @client.send_video(phone_number, promo_video_url, "Watch this exciting video!")
    end

    # Follow up with action buttons
    @client.send_buttons(
      phone_number,
      "Don't miss out on this amazing deal!",
      [
        { id: 'buy_now', title: '🛒 Buy Now' },
        { id: 'more_info', title: 'ℹ️ More Info' },
        { id: 'remind_later', title: '⏰ Remind Later' }
      ]
    )
  end

  # Handle media uploads with processing
  def process_uploaded_media(media_id, media_type, user_phone)
    begin
      # Download the media from WhatsApp
      media_url = @client.get_media_url(media_id)
      media_content = @client.download_media(media_id) if media_url

      if media_content
        # Upload to your cloud storage (S3, Google Cloud, etc.)
        cloud_url = upload_to_cloud_storage(media_content, media_type, media_id)
        
        # Process based on media type
        case media_type
        when 'image'
          process_image(cloud_url, user_phone)
        when 'document'
          process_document(cloud_url, user_phone)
        when 'audio'
          process_audio(cloud_url, user_phone)
        when 'video'
          process_video(cloud_url, user_phone)
        end
        
        Rails.logger.info "Successfully processed #{media_type} from #{user_phone}"
      end
    rescue => e
      Rails.logger.error "Error processing media: #{e.message}"
      @client.send_text(user_phone, "Sorry, I couldn't process your file. Please try again.")
    end
  end

  # Send personalized content based on user data
  def send_personalized_content(phone_number, user_id)
    # Get user's preferred content from your system
    user_content = fetch_user_content(user_id)
    
    # Send personalized image
    if user_content[:image_url]
      @client.send_image(phone_number, user_content[:image_url], user_content[:image_caption])
    end
    
    # Send personalized document
    if user_content[:document_url]
      @client.send_document(phone_number, user_content[:document_url], user_content[:document_description])
    end
  end

  # Send real-time generated content
  def send_qr_code(phone_number, data)
    # Generate QR code and get URL (using your QR service)
    qr_url = generate_qr_code_url(data)
    
    @client.send_image(phone_number, qr_url, "Here's your QR code!")
  end

  # Send chart/graph from analytics service
  def send_analytics_chart(phone_number, chart_type, period)
    # Generate chart URL from your analytics service
    chart_url = generate_analytics_chart_url(chart_type, period)
    
    @client.send_image(phone_number, chart_url, "#{chart_type.humanize} for #{period}")
  end

  private

  def upload_to_cloud_storage(content, media_type, media_id)
    # Your cloud storage upload logic here
    # Return the public URL of the uploaded file
    "https://storage.example.com/uploads/#{media_id}.#{get_file_extension(media_type)}"
  end

  def process_image(cloud_url, user_phone)
    # Your image processing logic here
    @client.send_text(user_phone, "Thanks for the image! I've processed it successfully. ✅")
  end

  def process_document(cloud_url, user_phone)
    # Your document processing logic here
    @client.send_text(user_phone, "Document received and processed! 📄")
  end

  def process_audio(cloud_url, user_phone)
    # Your audio processing logic here
    @client.send_text(user_phone, "Audio message processed! 🎵")
  end

  def process_video(cloud_url, user_phone)
    # Your video processing logic here
    @client.send_text(user_phone, "Video processed successfully! 🎥")
  end

  def fetch_user_content(user_id)
    # Fetch personalized content URLs from your database
    {
      image_url: "https://cdn.example.com/personal/#{user_id}/welcome.jpg",
      image_caption: "Your personalized welcome image!",
      document_url: "https://storage.example.com/personal/#{user_id}/guide.pdf",
      document_description: "Your personalized guide"
    }
  end

  def generate_qr_code_url(data)
    # Generate QR code URL using your service (or external API like QR Server)
    "https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=#{CGI.escape(data)}"
  end

  def generate_analytics_chart_url(chart_type, period)
    # Generate chart URL from your analytics service
    "https://charts.example.com/api/generate?type=#{chart_type}&period=#{period}"
  end

  def get_file_extension(media_type)
    case media_type
    when 'image' then 'jpg'
    when 'document' then 'pdf'
    when 'audio' then 'mp3'
    when 'video' then 'mp4'
    else 'bin'
    end
  end
end

# ============================================================================
# USAGE IN CONTROLLERS
# ============================================================================

class NotificationController < ApplicationController
  def send_media_notification
    service = WhatsAppMediaService.new
    
    # Send welcome package to new users
    service.send_welcome_package(params[:phone_number], params[:user_name])
    
    render json: { status: 'sent' }
  end
  
  def send_order_confirmation
    service = WhatsAppMediaService.new
    
    # Get invoice URL from your system (could be from S3, Google Cloud, etc.)
    invoice_url = get_invoice_url(params[:order_id])
    
    service.send_order_confirmation(
      params[:phone_number], 
      params[:order_id], 
      invoice_url
    )
    
    render json: { status: 'sent' }
  end

  def send_promo
    service = WhatsAppMediaService.new
    
    # Promotional content from CDN
    promo_image = "https://cdn.example.com/promos/#{params[:promo_id]}/banner.jpg"
    promo_video = "https://cdn.example.com/promos/#{params[:promo_id]}/video.mp4"
    
    service.send_promotion(params[:phone_number], promo_image, promo_video)
    
    render json: { status: 'sent' }
  end

  def send_qr_code
    service = WhatsAppMediaService.new
    service.send_qr_code(params[:phone_number], params[:qr_data])
    
    render json: { status: 'sent' }
  end

  private

  def get_invoice_url(order_id)
    # Your logic to get invoice URL from cloud storage
    "https://storage.example.com/invoices/#{order_id}.pdf"
  end
end 
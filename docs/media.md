# Media Support

FlowChat supports rich media attachments for enhanced conversational experiences with automatic cross-platform optimization.

## Supported Media Types

- **📷 Images** (`type: :image`) - Photos, screenshots, diagrams
- **📄 Documents** (`type: :document`) - PDFs, forms, receipts  
- **🎥 Videos** (`type: :video`) - Tutorials, demos, explanations
- **🎵 Audio** (`type: :audio`) - Voice messages, recordings
- **😊 Stickers** (`type: :sticker`) - Fun visual elements

## Basic Usage

```ruby
class ProductFlow < FlowChat::Flow
  def main_page
    # Text input with context image
    feedback = app.screen(:feedback) do |prompt|
      prompt.ask "What do you think of our new product?",
        media: {
          type: :image,
          url: "https://cdn.example.com/products/new_product.jpg"
        }
    end

    # Send informational media
    app.say "Thanks for your feedback! Here's what's coming next:",
      media: {
        type: :video,
        url: "https://videos.example.com/roadmap.mp4"
      }

    # Document with filename
    app.say "Here's your receipt:",
      media: {
        type: :document,
        url: "https://api.example.com/receipt.pdf",
        filename: "receipt.pdf"
      }
  end
end
```

## Media Hash Format

```ruby
{
  type: :image,        # Required: :image, :document, :audio, :video, :sticker
  url: "https://...",  # Required: URL to the media file OR WhatsApp media ID
  filename: "doc.pdf"  # Optional: Only for documents
}
```

## Using WhatsApp Media IDs

For better performance and to avoid external dependencies, you can upload files to WhatsApp and use the media ID:

```ruby
# Upload a file first
client = FlowChat::Whatsapp::Client.new(config)
media_id = client.upload_media('path/to/image.jpg', 'image/jpeg')

# Then use the media ID in your flow
app.screen(:product_demo) do |prompt|
  prompt.ask "What do you think?",
    media: {
      type: :image,
      url: media_id  # Use the media ID instead of URL
    }
end
```

## WhatsApp Client Media Methods

The WhatsApp client provides methods for uploading and sending media:

```ruby
client = FlowChat::Whatsapp::Client.new(config)

# Upload media and get media ID
media_id = client.upload_media('image.jpg', 'image/jpeg')
media_id = client.upload_media(file_io, 'image/jpeg', 'photo.jpg')

# Send media directly
client.send_image("+1234567890", "https://example.com/image.jpg", "Caption")
client.send_image("+1234567890", media_id, "Caption")

# Send document with MIME type and filename
client.send_document("+1234567890", "https://example.com/doc.pdf", "Your receipt", "receipt.pdf", "application/pdf")

# Send other media types
client.send_video("+1234567890", "https://example.com/video.mp4", "Demo video", "video/mp4")
client.send_audio("+1234567890", "https://example.com/audio.mp3", "audio/mpeg")
client.send_sticker("+1234567890", "https://example.com/sticker.webp", "image/webp")
```

## Cross-Platform Behavior

### WhatsApp Experience
- Media is sent directly to the chat
- Prompt text becomes the media caption
- Rich, native messaging experience

### USSD Experience  
- Media URL is included in text message
- Graceful degradation with clear media indicators
- Users can access media via the provided link

```ruby
# This code works on both platforms:
app.screen(:help) do |prompt|
  prompt.ask "Describe your issue:",
    media: {
      type: :image,
      url: "https://support.example.com/help_example.jpg"
    }
end
```

**WhatsApp Result:** Image sent with caption "Describe your issue:"

**USSD Result:** 
```
📷 Image: https://support.example.com/help_example.jpg

Describe your issue:
```

## Advanced Examples

### Dynamic Media Based on User Context

```ruby
class SupportFlow < FlowChat::Flow
  def show_help
    user_level = determine_user_level
    
    help_media = case user_level
    when :beginner
      { type: :video, url: "https://help.example.com/beginner_guide.mp4" }
    when :advanced
      { type: :document, url: "https://help.example.com/advanced_manual.pdf", filename: "advanced_manual.pdf" }
    else
      { type: :image, url: "https://help.example.com/quick_reference.jpg" }
    end
    
    app.say "Here's help tailored for you:", media: help_media
  end
end
```

See [examples/whatsapp_media_examples.rb](../examples/whatsapp_media_examples.rb) for complete media implementation examples. 
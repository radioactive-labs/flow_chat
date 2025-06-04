# Media Prompts Examples
# This file demonstrates how to attach media to prompts in FlowChat

# ============================================================================
# BASIC MEDIA PROMPTS
# ============================================================================

class MediaPromptFlow < FlowChat::Flow
  def main_page
    # ✅ Simple text input with attached image
    # The prompt text becomes the image caption
    app.screen(:feedback) do |prompt|
      prompt.ask "What do you think of our new product?",
        media: {
          type: :image,
          url: "https://cdn.example.com/products/new_product.jpg"
        }
    end

    # ✅ Send media message with say
    app.say "Thank you for your feedback! Here's what's coming next:",
      media: {
        type: :video,
        url: "https://videos.example.com/roadmap.mp4"
      }
  end
end

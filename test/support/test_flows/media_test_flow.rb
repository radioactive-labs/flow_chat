module FlowChat
  module TestSupport
    module TestFlows
      class MediaTestFlow < FlowChat::Flow
        def test_ask_with_image
          app.screen(:product_feedback) do |prompt|
            prompt.ask "What do you think of this product?", media: {
              type: :image,
              url: "https://example.com/help.jpg"
            }
          end
        end

        def test_say_with_document
          app.screen(:send_document) do |prompt|
            prompt.say "Here's your receipt:", media: {
              type: :document,
              url: "https://example.com/receipt.pdf",
              filename: "receipt.pdf"
            }
          end
        end

        def test_ask_with_validation
          app.screen(:age_verification) do |prompt|
            prompt.ask "Enter your age:",
              media: {type: :image, url: "https://example.com/age_verification.jpg"},
              validate: ->(input) { "Must be 18 or older" unless input.to_i >= 18 },
              transform: ->(input) { input.to_i }
          end
        end

        def test_say_sticker
          app.screen(:send_sticker) do |prompt|
            prompt.say "Thanks for your order!", media: {
              type: :sticker,
              url: "https://example.com/happy.webp"
            }
          end
        end

        def test_say_with_media_type(type, url)
          # Use a unique screen name for each test to avoid duplication
          screen_name = "send_media_#{type}_#{url.gsub(/[^a-zA-Z0-9]/, "_")}"
          app.screen(screen_name.to_sym) do |prompt|
            prompt.say "Check this out:", media: {
              type: type,
              url: url
            }
          end
        end

        def test_cross_platform_ask(media_hash)
          app.screen(:cross_platform_test) do |prompt|
            prompt.ask "Rate this product:", media: media_hash
          end
        end

        def test_ask_without_media
          app.screen(:name_input) do |prompt|
            prompt.ask "What's your name?"
          end
        end

        def complex_media_workflow
          step1 = app.screen(:step1) do |prompt|
            prompt.ask "Step 1: Choose your preference", media: {
              type: :image,
              url: "https://example.com/step1.jpg"
            }
          end

          step2 = app.screen(:step2) do |prompt|
            prompt.ask "Step 2: Confirm your choice: #{step1}", media: {
              type: :document,
              url: "https://example.com/confirmation.pdf"
            }
          end

          app.screen(:final_message) do |prompt|
            prompt.say "Workflow complete! You chose: #{step1}, confirmed: #{step2}", media: {
              type: :video,
              url: "https://example.com/thank_you.mp4"
            }
          end
        end

        def test_media_with_url
          app.screen(:url_test) do |prompt|
            prompt.ask "Test with URL:", media: {
              type: :image,
              url: "https://example.com/image.jpg"
            }
          end
        end
      end
    end
  end
end

require "net/http"
require "uri"

module FlowChat
  # Value object wrapping a single inbound media item parsed by a gateway.
  # Normalizes cross-platform differences (WhatsApp media-id, Telegram file_id,
  # Intercom/HTTP direct URL) behind #url and #download.
  class Media
    attr_reader :platform, :client

    def initialize(data, platform:, client: nil)
      @data = data
      @platform = platform
      @client = client
    end

    def type
      @data[:type]
    end

    def mime_type
      @data[:mime_type]
    end

    def caption
      @data[:caption]
    end

    def filename
      @data[:filename] || @data[:file_name]
    end

    def id
      @data[:id]
    end

    def file_id
      @data[:file_id]
    end

    def [](key)
      @data[key]
    end

    def to_h
      @data.dup
    end

    # Resolve a fetchable URL for the media.
    def url
      case platform
      when :whatsapp then client.get_media_url(id)
      when :telegram then client.file_url(file_id)
      else @data[:url]
      end
    end

    # Fetch the raw bytes of the media.
    def download
      case platform
      when :whatsapp then client.download_media(id)
      when :telegram then client.download_file(file_id)
      else fetch(url)
      end
    end

    private

    def fetch(resource_url)
      return nil unless resource_url

      uri = URI(resource_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      response = http.get(uri.request_uri)
      response.body if response.is_a?(Net::HTTPSuccess)
    rescue => e
      FlowChat.logger.warn { "Media: download failed for #{resource_url}: #{e.message}" }
      nil
    end
  end
end

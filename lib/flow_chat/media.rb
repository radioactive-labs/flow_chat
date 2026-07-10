require "net/http"
require "uri"

module FlowChat
  # Value object wrapping a single inbound media item parsed by a gateway.
  # Normalizes cross-platform differences (WhatsApp media-id, Telegram file_id,
  # Intercom/HTTP direct URL) behind #url and #download.
  class Media
    # Maps platform-native media types to a canonical, cross-platform set.
    # Telegram uses :photo/:voice where WhatsApp uses :image/:audio.
    NORMALIZED_TYPES = {photo: :image, voice: :audio}.freeze

    # The canonical media types FlowChat recognizes across platforms. Gateways
    # that accept a caller-supplied type (e.g. HTTP) validate against this set.
    CANONICAL_TYPES = %i[image video audio document sticker].freeze

    attr_reader :platform, :client

    def initialize(data, platform:, client: nil)
      @data = data
      @platform = platform
      @client = client
    end

    # Canonical, cross-platform media type (:image, :video, :audio, :document, :sticker).
    def type
      NORMALIZED_TYPES.fetch(raw_type, raw_type)
    end

    # The platform-native type as parsed by the gateway (e.g. :photo, :voice on Telegram).
    def raw_type
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

    # Resolve a fetchable URL for the media. Memoized so repeated reads don't
    # re-issue the platform lookup (WhatsApp get_media_url / Telegram getFile).
    def url
      @url ||= case platform
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

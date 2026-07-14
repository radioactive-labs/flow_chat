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

    # Serialize without the live platform client (a network object that may not
    # marshal). This keeps a Media — and any FlowChat::Input holding it — safe to
    # store in a session store. A deserialized Media has no client, so #url and
    # #download degrade to nil rather than raising.
    def marshal_dump
      {data: @data, platform: @platform}
    end

    def marshal_load(state)
      @data = state[:data]
      @platform = state[:platform]
      @client = nil
    end

    # Resolve a fetchable URL for the media. Memoized so repeated reads don't
    # re-issue the platform lookup (WhatsApp get_media_url / Telegram getFile).
    # Returns nil (rather than raising) if the lookup fails, matching #download.
    def url
      @url ||= case platform
      when :whatsapp then client.get_media_url(id)
      when :telegram then client.file_url(file_id)
      else @data[:url]
      end
    rescue => e
      FlowChat.logger.warn { "Media: url resolution failed: #{e.message}" }
      nil
    end

    # Fetch the raw bytes of the media, or nil on failure (uniform across
    # platforms). WhatsApp needs the client to attach auth headers; every other
    # platform (Telegram, Intercom, HTTP) exposes a token-in-URL or public link,
    # so we fetch the already-memoized #url directly — avoiding a second getFile
    # round-trip on Telegram.
    def download
      case platform
      when :whatsapp then client.download_media(id)
      else fetch(url)
      end
    rescue => e
      FlowChat.logger.warn { "Media: download failed: #{e.message}" }
      nil
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

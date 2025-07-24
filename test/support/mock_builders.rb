module FlowChat
  module TestSupport
    module MockBuilders
      # Build a complete mock HTTP response
      def build_mock_response(status: 200, body: {}, headers: {})
        response = Minitest::Mock.new
        response.expect(:code, status.to_s)
        response.expect(:body, body.is_a?(String) ? body : body.to_json)
        response.expect(:headers, headers)
        response
      end

      # Build a mock Rails cache store
      def build_mock_cache_store
        Class.new do
          def initialize
            @data = {}
          end

          def read(key)
            @data[key]
          end

          def write(key, value, options = {})
            @data[key] = value
          end

          def delete(key)
            @data.delete(key)
          end

          def clear
            @data.clear
          end

          def exist?(key)
            @data.key?(key)
          end
        end.new
      end

      # Build a mock ActiveJob
      def build_mock_job_class
        Class.new do
          class << self
            attr_accessor :performed_jobs
          end

          self.performed_jobs = []

          def self.perform_later(*args)
            performed_jobs << {args: args, performed_at: Time.now}
            new
          end

          def self.clear_performed_jobs
            performed_jobs.clear
          end
        end
      end

      # Build a mock gateway configuration
      def build_mock_gateway_config(overrides = {})
        config = Minitest::Mock.new
        config.expect(:access_token, overrides[:access_token] || "test_token")
        config.expect(:webhook_secret, overrides[:webhook_secret] || "test_secret")
        config.expect(:api_version, overrides[:api_version] || "v1")
        config.expect(:base_url, overrides[:base_url] || "https://api.example.com")
        config
      end

      # Build a mock instrumentation subscriber
      def build_mock_subscriber
        Class.new do
          attr_reader :events

          def initialize
            @events = []
          end

          def call(name, started, finished, unique_id, payload)
            @events << {
              name: name,
              started: started,
              finished: finished,
              duration: finished - started,
              payload: payload
            }
          end

          def clear
            @events.clear
          end

          def find_events(name)
            @events.select { |e| e[:name] == name }
          end
        end.new
      end

      # Build a mock HTTP client
      def build_mock_http_client
        Class.new do
          attr_reader :requests

          def initialize
            @requests = []
            @responses = {}
          end

          def stub_response(method, url, response)
            key = "#{method.to_s.upcase}:#{url}"
            @responses[key] = response
          end

          def request(method, url, options = {})
            @requests << {method: method, url: url, options: options}
            key = "#{method.to_s.upcase}:#{url}"
            @responses[key] || build_default_response
          end

          def get(url, options = {})
            request(:get, url, options)
          end

          def post(url, options = {})
            request(:post, url, options)
          end

          def put(url, options = {})
            request(:put, url, options)
          end

          def delete(url, options = {})
            request(:delete, url, options)
          end

          def clear
            @requests.clear
            @responses.clear
          end

          private

          def build_default_response
            OpenStruct.new(code: "200", body: "{}", headers: {})
          end
        end.new
      end
    end
  end
end

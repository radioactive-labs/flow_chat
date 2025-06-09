$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "flow_chat"
require "minitest/autorun"
require "minitest/reporters"
require "active_support/core_ext/object/blank"
require "active_support/core_ext/hash/indifferent_access"
require "active_support/core_ext/string/inflections"
require "active_support/core_ext/string/filters"
require "active_support/core_ext/enumerable"
require "active_support/core_ext/numeric/time"
require "ostruct"

# Load test support files
require_relative "support/base_test_job"
require_relative "support/test_whatsapp_job"

# Use a more readable test reporter
Minitest::Reporters.use! [Minitest::Reporters::DefaultReporter.new(color: true)]

# Configure cache for testing if not already set
unless FlowChat::Config.cache
  FlowChat::Config.cache = begin
    # Simple in-memory cache for testing
    cache = Object.new
    data = {}

    cache.define_singleton_method(:read) { |key| data[key] }
    cache.define_singleton_method(:write) { |key, value, options = {}| data[key] = value }
    cache.define_singleton_method(:delete) { |key| data.delete(key) }
    cache.define_singleton_method(:exist?) { |key| data.key?(key) }
    cache.define_singleton_method(:clear) { data.clear }

    cache
  end
end

# Mock Rails environment for testing
module Rails
  def self.logger
    @logger ||= begin
      require "logger"
      Logger.new($stdout, level: Logger::WARN)
    end
  end

  def self.env
    @env ||= OpenStruct.new(development?: false, test?: true)
  end
end

# Test helper methods
module TestHelpers
  def mock_controller
    @mock_controller ||= begin
      controller = OpenStruct.new(
        params: {},
        request: OpenStruct.new(raw_post: "")
      )
      # Add session method that returns a hash
      def controller.session
        @session ||= {}
      end
      controller
    end
  end

  def mock_ussd_request(input: "", msisdn: "256700000000", session_id: "test123")
    {
      "input" => input,
      "msisdn" => msisdn,
      "sessionId" => session_id,
      "serviceCode" => "*123#"
    }
  end

  def create_test_session_store
    Class.new do
      def initialize(context = nil)
        @data = {}
        @context = context
      end

      def get(key)
        @data[key.to_s]
      end

      def set(key, value)
        @data[key.to_s] = value
      end

      def delete(key)
        @data.delete(key.to_s)
      end

      def clear
        @data.clear
      end
    end.new
  end

  def create_test_session_store_class
    Class.new do
      def initialize(context = nil)
        @data = {}
        @context = context
      end

      def get(key)
        @data[key.to_s]
      end

      def set(key, value)
        @data[key.to_s] = value
      end

      def delete(key)
        @data.delete(key.to_s)
      end

      def clear
        @data.clear
      end
    end
  end

  # Helper to stub constantize method properly
  def stub_constantize(class_name, mock_class)
    original_constantize = String.instance_method(:constantize)
    String.class_eval do
      define_method(:constantize) do
        if self == class_name
          mock_class
        else
          # For any other class, use the original behavior which may raise NameError
          original_constantize.bind_call(self)
        end
      end
    end

    yield
  ensure
    String.class_eval do
      define_method(:constantize, original_constantize)
    end
  end

  # Helper to stub constantize to raise NameError for specific class
  def stub_constantize_to_fail(class_name)
    original_constantize = String.instance_method(:constantize)
    String.class_eval do
      define_method(:constantize) do
        if self == class_name
          raise NameError, "uninitialized constant #{class_name}"
        else
          original_constantize.bind_call(self)
        end
      end
    end

    yield
  ensure
    String.class_eval do
      define_method(:constantize, original_constantize)
    end
  end
end

class Minitest::Test
  include TestHelpers
end

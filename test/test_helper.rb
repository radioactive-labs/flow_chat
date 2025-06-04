$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "flow_chat"
require "minitest/autorun"
require "minitest/reporters"
require "active_support/core_ext/object/blank"
require "active_support/core_ext/hash/indifferent_access"
require "active_support/core_ext/string/inflections"
require "ostruct"

# Use a more readable test reporter
Minitest::Reporters.use! [Minitest::Reporters::DefaultReporter.new(color: true)]

# Mock Rails environment for testing
module Rails
  def self.logger
    @logger ||= begin
      require 'logger'
      Logger.new(STDOUT, level: Logger::WARN)
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
      def initialize
        @data = {}
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
end

class Minitest::Test
  include TestHelpers
end 
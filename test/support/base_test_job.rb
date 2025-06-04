# Base test job class that mocks ActiveJob functionality for testing
class BaseTestJob
  # Job tracking
  @@performed_jobs = []

  # Mock ActiveJob class methods
  def self.queue_as(queue_name)
    @queue_name = queue_name
  end

  def self.retry_on(exception_class, options = {})
    @retry_config = {exception: exception_class, options: options}
  end

  def self.perform_later(*args)
    job_data = {class: name, args: args, performed_at: Time.now}
    @@performed_jobs << job_data
    new.perform(*args)
  end

  def self.perform_now(*args)
    new.perform(*args)
  end

  # Getters for test verification
  def self.queue_name
    @queue_name
  end

  def self.retry_config
    @retry_config
  end

  # Job tracking methods
  def self.performed_jobs
    @@performed_jobs
  end

  def self.clear_performed_jobs
    @@performed_jobs.clear
  end

  def self.job_count
    @@performed_jobs.count
  end

  def self.last_job
    @@performed_jobs.last
  end

  # Test helper methods
  def self.create_mock_logger
    logger = Object.new
    logged_messages = []

    logger.define_singleton_method(:info) { |msg| logged_messages << [:info, msg] }
    logger.define_singleton_method(:error) { |msg| logged_messages << [:error, msg] }
    logger.define_singleton_method(:warn) { |msg| logged_messages << [:warn, msg] }
    logger.define_singleton_method(:debug) { |msg| logged_messages << [:debug, msg] }
    logger.define_singleton_method(:logged_messages) { logged_messages }

    logger
  end

  def self.create_mock_whatsapp_client
    client = Object.new
    sent_messages = []

    client.define_singleton_method(:send_message) { |phone, message|
      sent_messages << [phone, message]
      {"messages" => [{"id" => "test_#{rand(1000)}"}]}
    }
    client.define_singleton_method(:send_text) { |phone, text|
      sent_messages << [phone, [:text, text]]
      true
    }
    client.define_singleton_method(:sent_messages) { sent_messages }

    client
  end

  # Mock instance methods if needed
  def perform(*args)
    raise NotImplementedError, "Subclasses must implement #perform"
  end
end

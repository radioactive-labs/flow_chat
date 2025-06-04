# Example Background Jobs for WhatsApp Response Delivery
# Add these to your Rails application

# Example: Basic WhatsApp Send Job
# Only handles sending responses - flows are processed synchronously in the controller
class WhatsappMessageJob < ApplicationJob
  include FlowChat::Whatsapp::SendJobSupport

  def perform(send_data)
    perform_whatsapp_send(send_data)
  end
end

# Example: Advanced WhatsApp Send Job with custom callbacks
class AdvancedWhatsappMessageJob < ApplicationJob
  include FlowChat::Whatsapp::SendJobSupport

  def perform(send_data)
    perform_whatsapp_send(send_data)
  end

  private

  # Override for custom success handling
  def on_whatsapp_send_success(send_data, result)
    Rails.logger.info "Successfully sent WhatsApp message to #{send_data[:msisdn]}"
    UserEngagementTracker.track_message_sent(phone: send_data[:msisdn])
  end

  # Override for custom error handling
  def on_whatsapp_send_error(error, send_data)
    ErrorTracker.notify(error, user_phone: send_data[:msisdn])
  end
end

# Example: Priority send job for urgent messages
class UrgentWhatsappSendJob < ApplicationJob
  include FlowChat::Whatsapp::SendJobSupport

  queue_as :urgent_whatsapp  # Different queue for priority
  retry_on StandardError, wait: 1.second, attempts: 5  # Override retry policy

  def perform(send_data)
    perform_whatsapp_send(send_data)
  end

  private

  # Override error handling for urgent messages
  def handle_whatsapp_send_error(error, send_data, config = nil)
    # Immediately escalate urgent message failures
    AlertingService.send_urgent_alert(
      "Urgent WhatsApp send job failed",
      error: error.message,
      user: send_data[:msisdn]
    )

    # Still send user notification
    super
  end
end

# Example: Multi-tenant send job
class MultiTenantWhatsappSendJob < ApplicationJob
  include FlowChat::Whatsapp::SendJobSupport

  def perform(send_data)
    perform_whatsapp_send(send_data)
  end

  private

  # Override config resolution for tenant-specific configs
  def resolve_whatsapp_config(send_data)
    # Try tenant-specific config first
    tenant_name = extract_tenant_from_phone(send_data[:msisdn])
    if tenant_name && FlowChat::Whatsapp::Configuration.exists?(tenant_name)
      return FlowChat::Whatsapp::Configuration.get(tenant_name)
    end

    # Fallback to default resolution
    super
  end

  def extract_tenant_from_phone(phone)
    # Extract tenant from phone number prefix or other identifier
    case phone
    when /^\+1800/
      :enterprise
    when /^\+1888/
      :premium
    else
      :standard
    end
  end
end

# Usage in Rails configuration
#
# Add to config/application.rb:
# config.active_job.queue_adapter = :sidekiq
#
# Add to config/initializers/flowchat.rb:
# FlowChat::Config.whatsapp.message_handling_mode = :background
# FlowChat::Config.whatsapp.background_job_class = 'WhatsappMessageJob'
#
# How it works:
# 1. Controller receives WhatsApp webhook
# 2. Flow is processed synchronously (maintains controller context)
# 3. Response is queued for async delivery via background job
# 4. Job only handles sending the response, not processing flows

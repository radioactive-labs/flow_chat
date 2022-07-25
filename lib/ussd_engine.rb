require "ussd_engine/version"
require "ussd_engine/config"
require "ussd_engine/session/redis_store"
require "ussd_engine/middleware/request_id"
require "ussd_engine/middleware/nalo_processor"
require "ussd_engine/middleware/nsano_processor"
require "ussd_engine/middleware/resumable_sessions"
require "ussd_engine/middleware/pagination"
require "ussd_engine/controller/mixin"
require "ussd_engine/simulator"

module UssdEngine
  def self.root
    __dir__
  end
end

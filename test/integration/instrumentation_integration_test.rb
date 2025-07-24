# Instrumentation integration tests have been split into focused modules
# for better organization and maintainability.
#
# The tests can now be found in:
# - test/integration/instrumentation/session_lifecycle_test.rb - Session lifecycle events
# - test/integration/instrumentation/gateway_flow_test.rb - Gateway and flow execution
# - test/integration/instrumentation/error_handling_test.rb - Error instrumentation
# - test/integration/instrumentation/ussd_pagination_test.rb - USSD-specific features
# - test/integration/instrumentation/concurrent_execution_test.rb - Concurrent requests
# - test/integration/instrumentation/resilience_test.rb - Edge cases and resilience
# - test/performance/instrumentation_benchmark_test.rb - Performance testing
#
# To run all instrumentation tests:
#   rake test TEST="test/integration/instrumentation/*_test.rb"
#
# To run performance tests:
#   ruby test/performance/instrumentation_benchmark_test.rb

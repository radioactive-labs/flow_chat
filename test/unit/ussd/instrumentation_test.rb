# USSD instrumentation tests have been split into focused modules
# for better organization and maintainability.
#
# The tests can now be found in:
# - test/unit/ussd/instrumentation/gateway_test.rb - Gateway message events
# - test/unit/ussd/instrumentation/pagination_test.rb - Pagination middleware events
# - test/unit/ussd/instrumentation/event_integrity_test.rb - Event completeness and integrity
#
# To run all USSD instrumentation tests:
#   rake test TEST="test/unit/ussd/instrumentation/*_test.rb"

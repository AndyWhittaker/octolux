#! /usr/bin/env ruby
# frozen_string_literal: true

require_relative 'boot'

octopus = Octopus.new(product_code: CONFIG['octopus']['product_code'],
                      tariff_code: CONFIG['octopus']['tariff_code'])
# if we have less than 6 hours of future $octopus tariff data, update it
octopus.update if octopus.stale?
unless octopus.price
  LOGGER.fatal 'No current Octopus price, aborting'
  exit 255
end

# rubocop:disable Lint/UselessAssignment

# FIXME: duplicated in mq.rb, could move to boot.rb?

# This is for the primary (master) inverter
lc = LuxController.new(host: CONFIG['lxp']['host'],
                       port: CONFIG['lxp']['port'],
                       serial: CONFIG['lxp']['serial'],
                       datalog: CONFIG['lxp']['datalog'])

lc_slave = LuxController.new(host: CONFIG['lxp']['host_slave'],
                       port: CONFIG['lxp']['port_slave'],
                       serial: CONFIG['lxp']['serial_slave'],
                       datalog: CONFIG['lxp']['datalog_slave'])

# MQTT
ls = LuxStatus.new(host: CONFIG['server']['connect_host'] || CONFIG['server']['host'],
                   port: CONFIG['server']['port'])

# rubocop:enable Lint/UselessAssignment

raise('rules.rb not found!') unless File.readable?('rules.rb')

instance_eval(File.read('rules.rb'), 'rules.rb')

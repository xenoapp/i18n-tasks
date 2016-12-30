# frozen_string_literal: true
if ENV['COVERAGE'] && !%w(rbx jruby).include?(RUBY_ENGINE)
  ENV['SIMPLECOV_NO_DEFAULTS'] = '1'
  require 'simplecov'
  SimpleCov.command_name 'RSpec'
  SimpleCov.root File.expand_path(File.join(File.dirname(__FILE__), '..'))
  require 'simplecov/defaults'
  SimpleCov::Formatter::HTMLFormatter.send(:define_method, :puts) { |*| }
end
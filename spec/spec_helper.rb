require 'bundler/setup'

$:.push File.expand_path("../lib", __FILE__)
require 'creeper'
require 'pry'

Creeper.logger = Creeper.error_logger = Logger.new(nil)

RSpec.configure do |config|
end
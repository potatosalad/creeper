#!/usr/bin/env creeper -j
#
# There are 2 ways to run this file:
# creeper -j jack.rb
# OR
# ./jack.rb
#
# If you remove the shebang, it can also be run with:
# ruby jack.rb

$LOAD_PATH.unshift(File.dirname(__FILE__) + '/../lib') unless $LOAD_PATH.include?(File.dirname(__FILE__) + '/../lib')

require 'creeper'

include Creeper::Creep

job('jack.work') do |*args|
  Creeper.logger.info "[JACK.WORK] #{$0.inspect} #{args.inspect}"
end

Creeper.work(:all, 1) unless defined?(Creeper::Launcher)
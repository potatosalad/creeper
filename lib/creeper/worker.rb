require 'creeper/client'
require 'creeper/core_ext'

module Creeper

  ##
  # Include this module in your worker class and you can easily create
  # asynchronous jobs:
  #
  # class HardWorker
  #   include Creeper::Worker
  #
  #   def perform(*args)
  #     # do some work
  #   end
  # end
  #
  # Then in your Rails app, you can do this:
  #
  #   HardWorker.perform_async(1, 2, 3)
  #
  # Note that perform_async is a class method, perform is an instance method.
  module Worker
    def self.included(base)
      base.extend(ClassMethods)
      base.class_attribute :creeper_options_hash
    end

    def logger
      Creeper.logger
    end

    module ClassMethods

      def creeper_legacy_queue(tube = nil)
        return @creeper_legacy_queue if tube.nil?
        (@creeper_legacy_queue = tube).tap do
          Creeper.job_descriptions[@creeper_legacy_queue] = self
        end
      end

      def perform_async(*args)
        client_push('class' => self, 'args' => args)
      end

      def perform_in(interval, *args)
        int = interval.to_f
        ts = (int < 1_000_000_000 ? Time.now.to_f + int : int)
        client_push('class' => self, 'args' => args, 'at' => ts)
      end
      alias_method :perform_at, :perform_in

      ##
      # Allows customization for this type of Worker.
      # Legal options:
      #
      #   :queue - use a named queue for this Worker, default 'default'
      #   :retry - enable the RetryJobs middleware for this Worker, default *true*
      #   :timeout - timeout the perform method after N seconds, default *nil*
      #   :backtrace - whether to save any error backtrace in the retry payload to display in web UI,
      #      can be true, false or an integer number of lines to save, default *false*
      def creeper_options(opts={})
        self.creeper_options_hash = get_creeper_options.merge(stringify_keys(opts || {}))
      end

      DEFAULT_OPTIONS = { 'retry' => true, 'queue' => 'default' }

      def get_creeper_options # :nodoc:
        self.creeper_options_hash ||= DEFAULT_OPTIONS
      end

      def stringify_keys(hash) # :nodoc:
        hash.keys.each do |key|
          hash[key.to_s] = hash.delete(key)
        end
        hash
      end

      def client_push(*args) # :nodoc:
        Creeper::Client.push(*args)
      end

    end
  end
end

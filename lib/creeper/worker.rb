require 'creeper'

require 'celluloid'
require 'celluloid/worker'

module Celluloid
  module Worker
    class Manager

      def crash_handler(actor, reason)
        return unless reason # don't restart workers that exit cleanly
        index = @idle.rindex(actor) # replace the old actor if possible
        if index
          @idle[index] = @worker_class.new_link(*@args)
        else
          @idle << @worker_class.new_link(*@args)
        end
      end

    end
  end
end

module Creeper
  class Worker

    include Celluloid::Worker

    attr_accessor :number, :started_at, :stopped_at
    attr_reader :jobs

    def initialize(jobs = nil)
      @jobs = jobs || Creeper.all_jobs
      @jobs = Creeper.all_jobs if @jobs == :all

      Creeper.register_worker(self)
      logger.info "[#{number}] Working #{self.jobs.size} jobs: [ #{self.jobs.join(' ')} ]"
    end

    def logger
      Creeper.logger
    end

    def error_logger
      Creeper.error_logger
    end

    ## beanstalk ##

    def beanstalk
      Creeper.beanstalk
    end

    def ignore(tube)
      beanstalk.ignore(tube)
    rescue Beanstalk::NotConnected => e
      disconnected(self, :ignore, tube) || raise
    end

    def list_tubes_watched(cached = false)
      beanstalk.list_tubes_watched
    rescue Beanstalk::NotConnected => e
      disconnected(self, :list_tubes_watched, cached) || raise
    end

    def reserve(timeout = nil)
      beanstalk.reserve(timeout)
    rescue Beanstalk::NotConnected => e
      disconnected(self, :reserve, timeout) || raise
    end

    def watch(tube)
      beanstalk.watch(tube)
    rescue Beanstalk::NotConnected => e
      disconnected(self, :watch, tube) || raise
    end

    ##

    def start
      prepare     if not prepared?
      return true if working?

      begin
        job = reserve Creeper.reserve_timeout
      rescue Beanstalk::TimedOut
        logger.warn "[#{number}] Back to the unemployment line"
        return false
      end

      Thread.current[:creeper_working] = true

      logger.debug "[#{number}] Got #{job.inspect}"

      work! job # asynchronously go to work
    end

    def work(job)

      name, data = JSON.parse(job.body)

      Creeper.start_work(self, data, name, job)

      begin
        Creeper.before_handlers_for(name).each do |handler|
          process(handler, data, name, job)
        end

        Creeper.handler_for(name).tap do |handler|
          process(handler, data, name, job)
        end

        Creeper.after_handlers_for(name).each do |handler|
          process(handler, data, name, job)
        end
      end

      job.delete

      Creeper.stop_work(self, data, name, job)

    rescue Beanstalk::NotConnected => e
      disconnected(self, :work, job) || raise
    rescue SystemExit => e
      job.release rescue nil
      Creeper.unregister_worker(self)
      raise
    rescue => e
      # Creeper.log_exception("[#{number}] loop error", e)

      job.bury rescue nil

      Creeper.error_work(self, data, name, job)

      begin
        Creeper.error_handlers_for(name).each do |handler|
          process(handler, data, name, job)
        end
      end

      Creeper.unregister_worker(self)

      raise
    ensure
      @started_at = nil
      @stopped_at = nil
      Thread.current[:creeper_working] = false
    end

    def process(handler, data, name, job)
      case handler.arity
      when 3
        handler.call(data, name, job)
      when 2
        handler.call(data, name)
      when 1
        handler.call(data)
      else
        handler.call
      end
    end

    ## flags ##

    def prepared?
      Thread.current[:creeper_prepared] == true
    end

    def working?
      Thread.current[:creeper_working] == true
    end

    ##

    protected

    def disconnected(target, method, *args, &block)
      Creeper.send(:disconnected, target, method, *args, &block)
    end

    def prepare
      jobs.each do |job|
        watch(job)
      end

      list_tubes_watched.each do |server, tubes|
        tubes.each do |tube|
          ignore(tube) unless jobs.include?(tube)
        end
      end

      Thread.current[:creeper_prepared] = true
    end

  end
end
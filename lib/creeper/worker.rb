require 'creeper'

require 'celluloid'
require 'celluloid/worker'

module Creeper
  class Worker

    include Celluloid::Worker

    attr_accessor :number
    attr_reader :jobs

    def initialize(jobs = nil)
      @jobs = jobs || Creeper.all_jobs

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
      disconnected(self, :reserve, timeout)
    end

    def watch(tube)
      beanstalk.watch(tube)
    rescue Beanstalk::NotConnected => e
      disconnected(self, :watch, tube) || raise
    end

    ##

    def work
      prepare if not prepared?
      return true if working?

      begin
        job = reserve Creeper.reserve_timeout
      rescue Beanstalk::TimedOut
        logger.warn "[#{number}] No job for me right now"
        return false
      end

      Thread.current[:creeper_working] = true

      logger.debug "[#{number}] Got #{job.inspect}"

      perform! job # asynchronously go to work
    end

    def perform(job)
      logger.debug "[#{number}] Working #{job.inspect}"

      name, data = JSON.parse(job.body)

      begin
        Creeper.before_handlers_for(name).each do |handler|
          call(handler, data, name, job)
        end

        Creeper.handler_for(name).tap do |handler|
          call(handler, data, name, job)
        end

        Creeper.after_handlers_for(name).each do |handler|
          call(handler, data, name, job)
        end
      end

      logger.debug "[#{number}] Deleting #{job.inspect}"

      job.delete

    ensure
      Thread.current[:creeper_working] = false
    end

    def call(handler, data, name, job)
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
      Creeper.disconnected(target, method, *args, &block)
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
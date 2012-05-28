require 'creeper'

require 'celluloid'
require 'creeper/celluloid_ext'

module Creeper

  at_exit { shutdown_workers }

  class Worker

    include Celluloid

    attr_accessor :number, :started_at, :stopped_at
    attr_reader :jobs

    def initialize(jobs = nil)
      @jobs = jobs || Creeper.all_jobs
      @jobs = Creeper.all_jobs if @jobs == :all

      Creeper.register_worker(self)
      Logger.info "#{prefix} Working #{self.jobs.size} jobs: [ #{self.jobs.join(' ')} ]"
    end

    def dump(job, name = nil, data = nil)
      "{ job: #{(job.inspect rescue nil)}, name: #{name.inspect rescue nil}, data: #{(data.inspect rescue nil)} }"
    end

    def prefix
      "[#{number}]"
    end

    def time_in_milliseconds
      ((stopped_at - started_at).to_f * 1000).to_i
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

    ## work ##

    def start(short_circuit = false)
      return false if short_circuit
      exit         if stopped?
      return true  if working?
      prepare      if not prepared?

      begin
        job = reserve Creeper.reserve_timeout
      rescue Beanstalk::TimedOut
        Logger.warn "#{prefix} Back to the unemployment line"
        return false
      end

      exit if stopped?

      Thread.current[:creeper_working] = true

      Logger.debug "#{prefix} Got #{job.inspect}"

      work! job # asynchronously go to work
    rescue => e
      job.release rescue nil
      Creeper.unregister_worker(self, "start loop error")
      raise
    end

    def stop
      Thread.current[:creeper_stopped] = true
    end

    def work(job)

      exit if stopped?

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
      disconnected(self, :work, job) || begin
        job.release rescue nil
        Creeper.unregister_worker(self)
        raise
      end
    rescue SystemExit => e
      job.release rescue nil
      Creeper.unregister_worker(self)
      raise
    rescue => e

      job.bury rescue nil

      Creeper.error_work(self, data, name, job)

      begin
        Creeper.error_handlers_for(name).each do |handler|
          process(handler, data, name, job)
        end
      end

      Creeper.unregister_worker(self, "work loop error, burying #{dump(job, name, data)}")

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

    ##

    ## flags ##

    def prepared?
      Thread.current[:creeper_prepared] == true
    end

    def stopped?
      Thread.current[:creeper_stopped] == true
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
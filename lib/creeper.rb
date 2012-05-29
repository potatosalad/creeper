require 'beanstalk-client'
require 'json'
require 'logger'
require 'thread'
require 'timeout'
require 'uri'

require 'creeper/version'

module Creeper

  class BadURL < RuntimeError; end

  HANDLERS = {
    named:        {},
    before_each:  [],
    before_named: {},
    after_each:   [],
    after_named:  {},
    error_each:   [],
    error_named:  {},
    finalizers:   []
  }

  WORKERS = {}

  ## default configuration ##

  @beanstalk_url   = ENV['BEANSTALK_URL'] || 'beanstalk://127.0.0.1/'
  @err_logger      = ::Logger.new($stderr)
  @out_logger      = ::Logger.new($stdout)
  @patience_soft   = 60
  @patience_hard   = 30
  @pool_size       = 2
  @retry_count     = 3
  @reserve_timeout = 1

  @lock = Mutex.new

  ##

  class << self

    ## configuration ##

    attr_reader   :lock
    attr_accessor :beanstalk_url, :error_logger, :logger, :patience_soft, :patience_hard, :pool_size, :reserve_timeout, :retry_count

    def worker_pool
      lock.synchronize do
        @worker_pool
      end
    end

    def worker_pool=(worker_pool)
      lock.synchronize do
        @worker_pool = worker_pool
      end
    end

    def shutdown?
      lock.synchronize do
        !!@shutdown
      end
    end

    def shutdown=(shutdown)
      lock.synchronize do
        @shutdown = shutdown
      end
    end

    ##

    ## connection ##

    def beanstalk
      Thread.current[:beanstalk_pool_connection] ||= connect
    end

    def beanstalk_addresses
      uris = beanstalk_url.split(/[\s,]+/)
      uris.map do |uri|
        beanstalk_host_and_port(uri)
      end
    end

    def connect(addresses = nil)
      Beanstalk::Pool.new(addresses || beanstalk_addresses)
    end

    def disconnect
      Thread.current[:beanstalk_pool_connection].close rescue nil
      Thread.current[:beanstalk_pool_connection] = nil
    end

    ##

    ## daemon ##

    def work(jobs = nil, size = nil)
      require 'creeper/worker'

      Creeper.pool_size = size || Creeper.pool_

      Creeper::Worker.work(jobs, Creeper.pool_size)
    end

    ##

    ## handlers ##

    def all_jobs
      lock.synchronize do
        HANDLERS[:named].keys
      end
    end

    def job(name, &block)
      lock.synchronize do
        HANDLERS[:named][name] = block
        HANDLERS[:before_named][name] ||= []
        HANDLERS[:after_named][name]  ||= []
        HANDLERS[:error_named][name]  ||= []
        HANDLERS[:named][name]
      end
    end

    def drop(name)
      lock.synchronize do
        HANDLERS[:named].delete(name)
        HANDLERS[:before_named].delete(name)
        HANDLERS[:after_named].delete(name)
        HANDLERS[:error_named].delete(name)
        true
      end
    end

    def handler_for(name)
      lock.synchronize do
        HANDLERS[:named][name]
      end
    end

    def before(name = nil, &block)
      if name and name != :each
        lock.synchronize do
          HANDLERS[:before_named][name] << block
        end
      else
        lock.synchronize do
          HANDLERS[:before_each] << block
        end
      end
    end

    def before_handlers_for(name)
      lock.synchronize do
        HANDLERS[:before_each] + HANDLERS[:before_named][name]
      end
    end

    def after(name = nil, &block)
      if name and name != :each
        lock.synchronize do
          HANDLERS[:after_named][name] << block
        end
      else
        lock.synchronize do
          HANDLERS[:after_each] << block
        end
      end
    end

    def after_handlers_for(name)
      lock.synchronize do
        HANDLERS[:after_each] + HANDLERS[:after_named][name]
      end
    end

    def error(name = nil, &block)
      if name and name != :each
        lock.synchronize do
          HANDLERS[:error_named][name] << block
        end
      else
        lock.synchronize do
          HANDLERS[:error_each] << block
        end
      end
    end

    def error_handlers_for(name)
      lock.synchronize do
        HANDLERS[:error_each] + HANDLERS[:error_named][name]
      end
    end

    def finalizer(&block)
      lock.synchronize do
        HANDLERS[:finalizers] << block
      end
    end

    def finalizers
      lock.synchronize do
        HANDLERS[:finalizers]
      end
    end

    ##

    ## queue ##

    def enqueue(job, data = {}, options = {})
      # OutLogger.debug "#{Thread.current[:actor].inspect} Enqueueing #{job.inspect}, #{data.inspect}"#\n#{Celluloid::Actor.all.pretty_inspect}"
      OutLogger.debug "[#{Thread.current[:actor] ? Thread.current[:actor].subject.number : nil}] Enqueueing #{job.inspect}, #{data.inspect}" if $DEBUG
      enqueue!(job, data, options)
    rescue Beanstalk::NotConnected => e
      disconnected(self, :enqueue, job, data, options)
    end

    def enqueue!(job, data = {}, options = {})
      priority    = options[:priority] || options[:pri] || 65536
      delay       = [ 0, options[:delay].to_i ].max
      time_to_run = options[:time_to_run] || options[:ttr] || 120

      beanstalk.use job
      beanstalk.put JSON.dump([ job, data ]), priority, delay, time_to_run
    end

    ##

    ## workers ##

    def error_work(worker, data, name, job)
      (worker.stopped_at = Time.now).tap do |stopped_at|
        error_message = "#{worker.prefix} Error after #{worker.time_in_milliseconds}ms #{worker.dump(job, name, data)}"
        OutLogger.error error_message
      end
    end

    def register_worker(worker)
      lock.synchronize do
        number = ((0..(WORKERS.keys.max || 0)+1).to_a - WORKERS.keys).first
        WORKERS[number] = worker.tap do
          worker.number = number
        end
      end
    end

    def shutdown_workers
      begin
        soft_shutdown_workers(Creeper.patience_soft)
      rescue Timeout::Error
        begin
          hard_shutdown_workers(Creeper.patience_hard)
        rescue Timeout::Error
          kill_shutdown_workers
        end
      end
    end

    def start_work(worker, data, name, job)
      (worker.started_at = Time.now).tap do |started_at|
        OutLogger.info "#{worker.prefix} Working #{worker.dump(job, name, data)}"
      end
    end

    def stop_work(worker, data, name, job)
      (worker.stopped_at = Time.now).tap do |stopped_at|
        OutLogger.info "#{worker.prefix} Finished in #{worker.time_in_milliseconds}ms #{worker.dump(job, name, data)}"
      end
    end

    def unregister_worker(worker, reason = nil)
      reason ||= 'Stopping'
      OutLogger.info "#{worker.prefix} #{reason}"
      lock.synchronize do
        WORKERS.delete(worker.number)
      end
    end

    ##

    protected

    def beanstalk_host_and_port(uri_string)
      uri = URI.parse(uri_string)
      raise(BadURL, uri_string) if uri.scheme != 'beanstalk'
      "#{uri.host}:#{uri.port || 11300}"
    end

    def disconnected(target, method, *args, &block)
      Thread.current[:beanstalk_connection_retries] ||= 0

      if Thread.current[:beanstalk_connection_retries] >= retry_count
        OutLogger.error "Unable to connect to beanstalk after #{Thread.current[:beanstalk_connection_retries]} attempts"
        Thread.current[:beanstalk_connection_retries] = 0
        return false
      end

      disconnect

      Thread.current[:beanstalk_connection_retries] += 1

      sleep Thread.current[:beanstalk_connection_retries] * 2

      target.send(method, *args, &block)
    end

    def soft_shutdown_workers(timeout)
      Timeout.timeout(timeout) do
        actors = Celluloid::Actor.all
        OutLogger.info "Gracefully stopping #{actors.size} actors..." if actors.size > 0

        # Attempt to shut down the supervision tree, if available
        Celluloid::Supervisor.root.terminate if Celluloid::Supervisor.root

        # Actors cannot self-terminate, you must do it for them
        starts = working_actors.map do |actor|
          begin
            if actor.alive?
              actor.stop! # fire and forget for those already working
              actor.future(:start, true) # ensures that the mailbox is cleared out
            end
          rescue Celluloid::DeadActorError, Celluloid::MailboxError
          end
        end.compact

        starts.each do |start|
          begin
            start.value
          rescue Celluloid::DeadActorError, Celluloid::MailboxError
          end
        end

        OutLogger.info "Graceful stop completed cleanly"
      end
    end

    def hard_shutdown_workers(timeout)
      Timeout.timeout(timeout) do
        actors = Celluloid::Actor.all
        OutLogger.info "Terminating #{actors.size} actors..." if actors.size > 0

        # Attempt to shut down the supervision tree, if available
        Celluloid::Supervisor.root.terminate if Celluloid::Supervisor.root

        pool_managers.each do |pool_manager|
          begin
            pool_manager.terminate
          rescue Celluloid::DeadActorError, Celluloid::MailboxError
          end
        end

        # Actors cannot self-terminate, you must do it for them
        working_actors.each do |actor|
          begin
            actor.terminate
          rescue Celluloid::DeadActorError, Celluloid::MailboxError
          end
        end

        OutLogger.info "Termination completed cleanly"
      end
    end

    def kill_shutdown_workers
      actors = Celluloid::Actor.all
      OutLogger.info "Killing #{actors.size} actors..." if actors.size > 0

      # Attempt to shut down the supervision tree, if available
      Celluloid::Supervisor.root.kill if Celluloid::Supervisor.root

      # Actors cannot self-terminate, you must do it for them
      Celluloid::Actor.all.each do |actor|
        begin
          actor.kill
          actor.join
        rescue Celluloid::DeadActorError, Celluloid::MailboxError
        end
      end

      OutLogger.info "Killing completed cleanly"
    end

    def pool_managers
      Celluloid::Actor.all.tap do |actors|
        actors.keep_if do |actor|
          actor.is_a?(Celluloid::PoolManager) rescue false
        end
      end
    end

    def working_actors
      Celluloid::Actor.all.tap do |actors|
        actors.delete_if do |actor|
          actor.is_a?(Celluloid::PoolManager) rescue false
        end
      end
    end

  end

end

require 'creeper/creep'
require 'creeper/err_logger'
require 'creeper/out_logger'
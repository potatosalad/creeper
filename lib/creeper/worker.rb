require 'creeper'

require 'celluloid'
require 'creeper/celluloid_ext'
# require 'em-jack'

Creeper.error_logger = Celluloid.logger

module Creeper

  at_exit { shutdown_workers }

  class Worker

    def self.work(jobs = nil, size = nil)

      size ||= Creeper.pool_size

      options = {
        size: size,
        args: [jobs]
      }

      Creeper.worker_pool = Creeper::Worker.pool(options)

      begin
        trap(:INT)  { Creeper.shutdown = true }
        trap(:TERM) { Creeper.shutdown = true }
        trap(:QUIT) { Creeper.shutdown = true }
        Creeper.worker_pool.start
      end until Creeper.shutdown?

      exit
    end

    # def self.em_work(jobs = nil, size = 2)

    #   options = {
    #     size: size,
    #     args: [jobs]
    #   }

    #   tubes = jobs_for(jobs)

    #   Creeper.worker_pool = Creeper::Worker.pool(options)

    #   sleep 1

    #   EM.run do
    #     trap(:INT)  { Creeper.shutdown = true; EM.stop }
    #     trap(:TERM) { Creeper.shutdown = true; EM.stop }
    #     trap(:QUIT) { Creeper.shutdown = true; EM.stop }

    #     jack = EMJack::Connection.new(Creeper.beanstalk_url)

    #     reserve_loop = ->(timeout) do
    #       r = jack.reserve(timeout)
    #       r.callback do |job|
    #         Creeper.worker_pool.work! job
    #         EM.next_tick { reserve_loop.call(timeout) }
    #       end
    #       r.errback do
    #         EM.next_tick { reserve_loop.call(timeout) }
    #       end
    #     end

    #     watch_tubes = ->(list) do
    #       if list.empty?
    #         reserve_loop.call(Creeper.reserve_timeout)
    #       else
    #         w = jack.watch(list.shift)
    #         w.callback do
    #           watch_tubes.call(list)
    #         end
    #       end
    #     end

    #     watch_tubes.call(tubes)

    #   end

    # end

    def self.jobs_for(jobs = nil)
      case jobs
      when :all, nil
        Creeper.all_jobs
      else
        Array(jobs)
      end
    end

    include Celluloid

    attr_accessor :number
    attr_reader   :jobs

    def initialize(jobs = nil)
      @jobs = self.class.jobs_for(jobs)

      Creeper.register_worker(self)
      Logger.info "#{prefix} Working #{self.jobs.size} jobs: [ #{self.jobs.join(' ')} ]"
    end

    def dump(job, name = nil, data = nil)
      "#{name.inspect rescue nil} { data: #{(data.inspect rescue nil)}, job: #{(job.inspect rescue nil)} }"
    end

    def prefix
      "[#{number_format % number} - #{'%x' % Thread.current.object_id}]"
    end

    def number_format
      "%#{Creeper.pool_size.to_s.length}d"
    end

    def time_in_milliseconds
      ((stopped_at - started_at).to_f * 1000).to_i
    end

    def started_at
      Thread.current[:creeper_started_at]
    end

    def started_at=(started_at)
      Thread.current[:creeper_started_at] = started_at
    end

    def stopped_at
      Thread.current[:creeper_stopped_at]
    end

    def stopped_at=(stopped_at)
      Thread.current[:creeper_stopped_at] = stopped_at
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
        Logger.debug "#{prefix} Back to the unemployment line" if $DEBUG
        return false
      end

      exit if stopped?

      Thread.current[:creeper_working] = true

      Logger.debug "#{prefix} Got #{job.inspect}" if $DEBUG

      work! job # asynchronously go to work
    rescue SystemExit => e
      job.release rescue nil
      Creeper.unregister_worker(self)
    rescue => e
      job.release rescue nil
      Creeper.unregister_worker(self, "start loop error")
      raise
    end

    def finalize
      Creeper.finalizers.each do |finalizer|
        begin
          case finalizer.arity
          when 1
            finalizer.call(self)
          else
            finalizer.call
          end
        rescue => e
          Logger.crash "#{prefix} finalizer error", e
        end
      end

    ensure
      Creeper.disconnect
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

      # start! unless stopped? or EM.reactor_running?
      start! unless stopped? # continue processing, even when end of links is reached

    rescue Beanstalk::NotConnected => e
      disconnected(self, :work, job) || begin
        job.release rescue nil
        Creeper.unregister_worker(self)
        raise
      end
    rescue SystemExit => e
      job.release rescue nil
      Creeper.unregister_worker(self)
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
      Thread.current[:creeper_started_at] = nil
      Thread.current[:creeper_stopped_at] = nil
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
      Thread.current[:creeper_stopped] == true || Creeper.shutdown?
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
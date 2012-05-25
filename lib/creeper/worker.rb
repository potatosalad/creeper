module Creeper
  class Worker

    ## utilities ##

    class NoJobsDefined < RuntimeError; end
    class NoSuchJob < RuntimeError; end
    class JobTimeout < RuntimeError; end
    class BadURL < RuntimeError; end

    def logger
      Creeper.logger
    end

    def log_exception(*args)
      Creeper.log_exception(*args)
    end

    def error_logger
      Creeper.error_logger
    end

    def log(msg)
      logger.info(msg)
    end

    def log_error(msg)
      error_logger.error(msg)
    end

    ##

    attr_reader   :options, :session, :thread
    attr_accessor :soft_quit, :working

    def initialize(options = {})#jobs = nil, parent_session = , session = nil)
      @options = options
    end

    ### config ###

    def session
      @session ||= Creeper::Session.new(options[:parent_session] || Creeper.default_session)
    end

    def soft_quit
      @soft_quit ||= false
    end
    alias :soft_quit? :soft_quit

    def working
      @working ||= false
    end
    alias :working? :working

    ###

    def beanstalk
      session.beanstalk
    end

    def clear!
      @soft_quit = false
      @working = false
      @session = nil
    end

    def prepare
      raise NoJobsDefined if session.handlers.empty?

      jobs   = session.all_jobs if options[:jobs] == :all
      jobs ||= options[:jobs] ? [*options[:jobs]] : session.all_jobs
      jobs   = session.all_jobs if jobs.empty?

      jobs.each do |job|
        raise(NoSuchJob, job) unless session.handlers.has_key?(job)
      end

      logger.info "Working #{jobs.size} jobs: [ #{jobs.join(' ')} ]"

      jobs.each { |job| beanstalk.watch(job) }

      beanstalk.list_tubes_watched.each do |server, tubes|
        tubes.each { |tube| beanstalk.ignore(tube) unless jobs.include?(tube) }
      end
    rescue Beanstalk::NotConnected => e
      log_exception("worker[#{@thread.inspect}] failed beanstalk connection", e)
    end

    def work
      prepare
      loop { work_one_job }
    end

    def work_one_job
      stop if soft_quit?

      job = beanstalk.reserve
      name, args = JSON.parse job.body
      log_job_begin(name, args)
      handler = session.handlers[name]
      raise(NoSuchJob, name) unless handler

      begin
        session.before_handlers.each do |block|
          block.call(name)
        end
        handler.call(args)
      end

      job.delete
      log_job_end(name, args)
    rescue Beanstalk::NotConnected => e
      log_exception("worker[#{@thread.inspect}] failed beanstalk connection", e)
    rescue SystemExit => e
      log_exception("worker[#{@thread.inspect}] exit", e)
      raise
    rescue => e
      log_exception("worker[#{@thread.inspect}] loop error", e)
      job.bury rescue nil
      args ||= []
      log_job_end(name, args, 'failed') if @job_begun
      if session.error_handler
        if session.error_handler.arity == 1
          session.error_handler.call(e)
        else
          session.error_handler.call(e, name, args)
        end
      end
    end

    def start
      @thread = Thread.new do
        work
      end
    end

    def stop
      logger.info "worker dying: (current=#{Thread.current.inspect}#{@thread.inspect}"
      session.disconnect
      sleep 1
      @thread.kill
    end

    protected

    def log_job_begin(name, args)
      @working = true
      args_flat = flatten_args(args)

      log [ "Working", name, args_flat ].join(' ')
      @job_begun = Time.now
    end

    def log_job_end(name, args, failed=false)
      @working = false
      ellapsed = Time.now - @job_begun
      ms = (ellapsed.to_f * 1000).to_i
      args_flat = flatten_args(args)
      log [ "Finished #{name} in #{ms}ms #{failed ? ' (failed)' : ''}", args_flat ].join(' ')
    end

    def flatten_args(args)
      unless args.empty?
        '(' + args.inject([]) do |accum, (key,value)|
          accum << "#{key}=#{value}"
        end.join(' ') + ')'
      else
        ''
      end
    end

  end
end
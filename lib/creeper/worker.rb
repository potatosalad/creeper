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
      failed_connection(e)
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
      log_job_end(name)
    rescue Beanstalk::NotConnected => e
      failed_connection(e)
    rescue SystemExit
      puts "FART"
      raise
    rescue => e
      log_error exception_message(e)
      job.bury rescue nil
      log_job_end(name, 'failed') if @job_begun
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
      logger.info "worker dying: #{Thread.current.inspect}"
      session.disconnect
      @thread.kill
    end

    protected

    def failed_connection(e)
      session.send(:failed_connection, e)
    end

    def exception_message(e)
      session.send(:exception_message, e)
    end

    def log_job_begin(name, args)
      @working = true
      args_flat = unless args.empty?
        '(' + args.inject([]) do |accum, (key,value)|
          accum << "#{key}=#{value}"
        end.join(' ') + ')'
      else
        ''
      end

      log [ "Working", name, args_flat ].join(' ')
      @job_begun = Time.now
    end

    def log_job_end(name, failed=false)
      @working = false
      ellapsed = Time.now - @job_begun
      ms = (ellapsed.to_f * 1000).to_i
      log "Finished #{name} in #{ms}ms #{failed ? ' (failed)' : ''}"
    end

  end
end
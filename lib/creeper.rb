require 'beanstalk-client'

require 'json'
require 'uri'
require 'timeout'

require 'fcntl'
require 'etc'
require 'stringio'
require 'kgio'

require 'logger'

require 'creeper/version'
require 'creeper/creep'
require 'creeper/session'
require 'creeper/worker'

module Creeper

  # These hashes map Threads to Workers
  RUNNERS = {}
  GRAVEYARD = {}

  SELF_PIPE = []

  # signal queue used for self-piping
  SIG_QUEUE = []

  # list of signals we care about and trap in Creeper
  QUEUE_SIGS = [ :WINCH, :QUIT, :INT, :TERM, :TTIN, :TTOU ]

  START_CTX = {
    :argv => ARGV.map { |arg| arg.dup },
    0 => $0.dup,
  }
  START_CTX[:cwd] = begin
    a = File.stat(pwd = ENV['PWD'])
    b = File.stat(Dir.pwd)
    a.ino == b.ino && a.dev == b.dev ? pwd : Dir.pwd
  rescue
    Dir.pwd
  end

  attr_accessor :logger, :error_logger
  attr_accessor :job_file, :jobs, :patience, :ready_pipe, :runner_count, :soft_quit, :timeout

  extend self
  extend Creeper::Creep

  ## utilities ##

  def logger
    @logger ||= Logger.new($stdout)
  end

  def log_exception(prefix, exc, logger = error_logger)
    message = exc.message
    message = message.dump if /[[:cntrl:]]/ =~ message
    logger.error "#{prefix}: #{message} (#{exc.class})"
    exc.backtrace.each { |line| logger.error(line) }
  end

  def error_logger
    @error_logger ||= Logger.new($stderr)
  end

  ##

  ## main process ##

  ### config ###

  def job_file=(job_file)
    (@job_file = job_file).tap do
      require File.expand_path(job_file) if job_file
    end
  end

  def patience
    @patience ||= 60
  end

  def runner_count
    @runner_count ||= 1
  end

  def runner_count=(value)
    (@runner_count = value).tap do
      reset_proc_name
    end
  end

  def soft_quit
    @soft_quit ||= false
  end
  alias :soft_quit? :soft_quit

  def soft_quit=(soft_quit)
    (@soft_quit = soft_quit).tap do
      awaken_creeper if soft_quit?
    end
  end

  def timeout
    @timeout ||= 30
  end

  ###

  def new(options = {})
    tap do
      options.each do |key, value|
        send("#{key}=", value) if respond_to?("#{key}=")
      end
    end
  end

  def work(jobs = nil, runner_count = 1)
    self.jobs, self.runner_count = jobs, runner_count

    default_session.beanstalk # check if we can connect to beanstalk

    start.join
  end

  def start
    init_self_pipe!
    QUEUE_SIGS.each do |sig|
      trap(sig) do
        logger.debug "creeper received #{sig}" if $DEBUG
        SIG_QUEUE << sig
        awaken_creeper
      end
    end

    logger.info "creeper starting"

    self
  end

  def join
    respawn = true
    last_check = Time.now

    reset_proc_name
    logger.info "creeper process ready"
    if ready_pipe
      ready_pipe.syswrite($$.to_s)
      ready_pipe = ready_pipe.close rescue nil
    end
    begin
      reap_all_runners
      case SIG_QUEUE.shift
      when nil
        # break if soft_quit?
        # avoid murdering runners after our master process (or the
        # machine) comes out of suspend/hibernation
        if (last_check + timeout) >= (last_check = Time.now)
          sleep_time = timeout - 1
        else
          sleep_time = timeout/2.0 + 1
          logger.debug("creeper waiting #{sleep_time}s after suspend/hibernation") if $DEBUG
        end
        maintain_runner_count if respawn
        logger.debug("creeper sleeping for #{sleep_time}s") if $DEBUG
        creeper_sleep(sleep_time)
      when :QUIT # graceful shutdown
        break
      when :TERM, :INT # immediate shutdown
        stop(false)
        break
      when :WINCH
        self.runner_count = 0
        logger.debug "WINCH: setting runner_count to #{runner_count}" if $DEBUG
      when :TTIN
        self.runner_count += 1
        logger.debug "TTIN: setting runner_count to #{runner_count}" if $DEBUG
      when :TTOU
        self.runner_count -= 1 if runner_count > 0
        logger.debug "TTOU: setting runner_count to #{runner_count}" if $DEBUG
      end
    rescue => e
      Creeper.log_exception("creeper loop error", e)
    end while true
    stop # gracefully shutdown all captains on our way out
    logger.info "creeper complete"
  end

  def stop(graceful = true)
    limit = Time.now + patience
    kill_all_runners
    until (RUNNERS.empty? && GRAVEYARD.empty?) || (n = Time.now) > limit
      reap_graveyard(graceful)
      sleep(0.1)
    end
    if n and n > limit
      logger.debug "creeper patience exceeded by #{n - limit} seconds (limit #{patience} seconds)" if $DEBUG
    end
    reap_graveyard(false)
    logger.debug graceful ? "creeper gracefully stopped" : "creeper hard stopped" if $DEBUG
  end

  private

  # wait for a signal hander to wake us up and then consume the pipe
  def creeper_sleep(sec)
    IO.select([ SELF_PIPE[0] ], nil, nil, sec) or return
    SELF_PIPE[0].kgio_tryread(11)
  end

  def awaken_creeper
    SELF_PIPE[1].kgio_trywrite('.') # wakeup creeper process from select
  end

  def init_self_pipe!
    SELF_PIPE.each { |io| io.close rescue nil }
    SELF_PIPE.replace(Kgio::Pipe.new)
    SELF_PIPE.each { |io| io.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC) }
  end

  def kill_all_runners
    RUNNERS.each do |thread, worker|
      GRAVEYARD[thread] = RUNNERS.delete(thread)
    end
  end

  def maintain_runner_count
    current_runner_count = RUNNERS.size - runner_count

    spawn_missing_runners if current_runner_count < 0
    murder_extra_runners  if current_runner_count > 0
    reap_all_runners
    reap_graveyard
  end

  def murder_extra_runners
    until RUNNERS.size == runner_count
      thread, worker = RUNNERS.shift
      if worker.working?
        logger.debug "creeper [murder] => soft quit" if $DEBUG
        worker.soft_quit = true
        GRAVEYARD[thread] = worker
      else
        logger.debug "creeper [murder] => hard quit" if $DEBUG
        thread.kill
        thread.join
      end
    end
  end

  def reap_all_runners
    RUNNERS.each do |thread, worker|
      GRAVEYARD[thread] = worker if not thread.alive?
    end
  end

  def reap_graveyard(graceful = true)
    GRAVEYARD.each do |thread, worker|
      if graceful and worker.working?
        logger.debug "creeper [graveyard] => soft quit" if $DEBUG
        worker.soft_quit = true
      else
        logger.debug "creeper [graveyard] => hard quit" if $DEBUG
        thread.kill rescue nil
        thread.join
        GRAVEYARD.delete(thread)
      end
    end
  end

  def spawn_missing_runners
    until RUNNERS.size == runner_count
      worker = Creeper::Worker.new(jobs: jobs)
      thread = worker.start
      RUNNERS[thread] = worker
    end
  end

  def reset_proc_name
    proc_name "creeper(#{$$}) [#{runner_count}]"
  end

  def proc_name(tag)
    if defined?(Navy) and defined?($officer)
      Creeper::START_CTX.merge!(Navy::Admiral::START_CTX)
      tag = "(#{$officer.captain.label}) officer[#{$officer.number}] #{tag}"
    end
    $0 = ([
      File.basename(Creeper::START_CTX[0]),
      tag
    ]).concat(Creeper::START_CTX[:argv]).join(' ')
  end

  ##

end

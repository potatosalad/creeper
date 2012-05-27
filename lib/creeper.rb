require 'beanstalk-client'
require 'json'
require 'thread'
require 'uri'

require 'creeper/version'

module Creeper

  extend self

  ## configuration ##

  attr_writer :beanstalk_url, :error_logger, :logger, :reserve_timeout, :retry_count

  def beanstalk_url
    @beanstalk_url ||= ENV['BEANSTALK_URL'] || 'beanstalk://localhost/'
  end

  def error_logger
    @error_logger ||= Logger.new($stderr)
  end

  def logger
    @logger ||= Logger.new($stdout)
  end

  def retry_count
    @retry_count ||= 3
  end

  def reserve_timeout
    @reserve_timeout ||= 1
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

  ## handlers ##

  HANDLERS = {
    named:        {},
    before_each:  [],
    before_named: {},
    after_each:   [],
    after_named:  {},
    error_each:   [],
    error_named:  {}
  }

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

  ##

  ## queue ##

  def enqueue(job, data = {}, options = {})
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

  ## threads/utilities ##

  def lock
    @lock ||= Mutex.new
  end

  def log_exception(prefix, exc, logger = nil)
    logger ||= error_logger
    message = exc.message
    message = message.dump if /[[:cntrl:]]/ =~ message
    logger.error "#{prefix}: #{message} (#{exc.class})"
    exc.backtrace.each { |line| logger.error(line) }
  end

  ##

  ## workers ##

  WORKERS = {}

  def register_worker(worker)
    lock.synchronize do
      number = ((0..(WORKERS.keys.max || 0)+1).to_a - WORKERS.keys).first
      WORKERS[number] = worker.tap do
        worker.number = number
      end
    end
  end

  def unregister_worker(worker)
    lock.synchronize do

    end
  end

  ##

  protected

  class BadURL < RuntimeError; end

  def beanstalk_host_and_port(uri_string)
    uri = URI.parse(uri_string)
    raise(BadURL, uri_string) if uri.scheme != 'beanstalk'
    "#{uri.host}:#{uri.port || 11300}"
  end

  def disconnected(target, method, *args, &block)
    Thread.current[:beanstalk_connection_retries] ||= 0

    if Thread.current[:beanstalk_connection_retries] >= retry_count
      error_logger.error "Unable to connect to beanstalk after #{Thread.current[:beanstalk_connection_retries]} attempts"
      Thread.current[:beanstalk_connection_retries] = 0
      return false
    end

    disconnect

    Thread.current[:beanstalk_connection_retries] += 1

    target.send(method, *args, &block)
  end

end

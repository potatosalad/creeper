module Creeper
  class Session

    attr_accessor :beanstalk, :beanstalk_url
    attr_accessor :before_handlers, :error_handler, :handlers

    def initialize(parent_session = nil)
      if parent_session
        @beanstalk_url   = parent_session.beanstalk_url
        @before_handlers = parent_session.before_handlers
        @error_handler   = parent_session.error_handler
        @handlers        = parent_session.handlers
      end

      @before_handlers ||= []
      @handlers        ||= {}
    end

    def clear!
      handlers.clear
      before_handlers.clear
      self.error_handler = nil
    end

    ## class methods ##

    def self.beanstalk_addresses(beanstalk_url)
      uris = beanstalk_url.split(/[\s,]+/)
      uris.map do |uri|
        beanstalk_host_and_port(uri)
      end
    end

    def self.beanstalk_host_and_port(uri_string)
      uri = URI.parse(uri_string)
      raise(BadURL, uri_string) if uri.scheme != 'beanstalk'
      "#{uri.host}:#{uri.port || 11300}"
    end

    def self.beanstalk_url
      ENV['BEANSTALK_URL'] || 'beanstalk://localhost/'
    end

    ##

    ## beanstalk ##

    class BadURL < RuntimeError; end

    def connect
      Beanstalk::Pool.new(beanstalk_addresses)
    end

    def disconnect
      beanstalk.close.tap do
        @beanstalk = nil
      end
    end

    def reconnect
      disconnect rescue nil
      beanstalk
    end

    def beanstalk
      @beanstalk ||= connect
    end

    def beanstalk_url
      @beanstalk_url ||= singleton_class.beanstalk_url
    end

    def beanstalk_addresses
      singleton_class.beanstalk_addresses(beanstalk_url)
    end

    ##

    ## handlers ##

    def job(name, &block)
      handlers[name] = block
    end

    def before(&block)
      before_handlers << block
    end

    def error(&block)
      self.error_handler = block
    end

    def all_jobs
      handlers.keys
    end

    ##

    ## queue ##

    def enqueue(job, args = {}, opts = {})
      pri   = opts[:pri]   || 65536
      delay = [0, opts[:delay].to_i].max  
      ttr   = opts[:ttr]   || 120
      beanstalk.use job
      beanstalk.put [ job, args ].to_json, pri, delay, ttr
    rescue Beanstalk::NotConnected => e
      failed_connection(e)
    end

    ##

    protected

    def failed_connection(e)
      log_error exception_message(e)
      log_error "*** Failed connection to #{beanstalk_url}"
      log_error "*** Check that beanstalkd is running (or set a different BEANSTALK_URL)"
    end

    def log(msg)
      Creeper.logger.info(msg)
    end

    def log_error(msg)
      Creeper.error_logger.error(msg)
    end

    def exception_message(e)
      msg = [ "Exception #{e.class} -> #{e.message}" ]

      base = File.expand_path(Dir.pwd) + '/'
      e.backtrace.each do |t|
        msg << "   #{File.expand_path(t).gsub(/#{base}/, '')}"
      end

      msg.join("\n")
    end

  end
end
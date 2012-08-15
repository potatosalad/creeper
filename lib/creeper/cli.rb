trap 'INT' do
  # Handle Ctrl-C in JRuby like MRI
  # http://jira.codehaus.org/browse/JRUBY-4637
  Creeper::CLI.instance.interrupt
end

trap 'TERM' do
  # Heroku sends TERM and then waits 10 seconds for process to exit.
  Creeper::CLI.instance.interrupt
end

trap 'QUIT' do
  Creeper.logger.info "Received QUIT, no longer accepting new work"
  mgr = Creeper::CLI.instance.manager
  if mgr
    mgr.stop!(shutdown: true, timeout: 8)
    mgr.wait(:shutdown)
    # Explicitly exit so busy Processor threads can't block
    # process shutdown.
    exit(0)
  end
end

trap 'USR1' do
  Creeper.logger.info "Received USR1, no longer accepting new work"
  mgr = Creeper::CLI.instance.manager
  mgr.stop! if mgr
end

trap 'TTIN' do
  Thread.list.each do |thread|
    Creeper.logger.info "Thread TID-#{thread.object_id.to_s(36)} #{thread['label']}"
    Creeper.logger.info thread.backtrace.join("\n")
  end
end

$stdout.sync = true

require 'yaml'
require 'singleton'
require 'optparse'
require 'celluloid'

require 'creeper'
require 'creeper/util'
require 'creeper/manager'
# require 'creeper/scheduled'

module Creeper
  class CLI
    include Util
    include Singleton

    # Used for CLI testing
    attr_accessor :code
    attr_accessor :manager

    def initialize
      @code = nil
      @interrupt_mutex = Mutex.new
      @interrupted = false
    end

    def parse(args=ARGV)
      @code = nil
      Creeper.logger

      cli = parse_options(args)
      config = parse_config(cli)
      options.merge!(config.merge(cli))

      Creeper.logger.level = Logger::DEBUG if options[:verbose]
      Celluloid.logger = nil unless options[:verbose]

      validate!
      write_pid
      boot_system
    end

    def run
      @manager = Creeper::Manager.new(options)
      begin
        logger.info 'Starting processing, hit Ctrl-C to stop'
        @manager.start!
        sleep
      rescue Interrupt
        logger.info 'Shutting down'
        @manager.stop!(:shutdown => true, :timeout => options[:timeout])
        @manager.wait(:shutdown)
        # Explicitly exit so busy Processor threads can't block
        # process shutdown.
        exit(0)
      end
    end

    def interrupt
      @interrupt_mutex.synchronize do
        unless @interrupted
          @interrupted = true
          Thread.main.raise Interrupt
        end
      end
    end

    private

    def die(code)
      exit(code)
    end

    def options
      Creeper.options
    end

    def detected_environment
      options[:environment] ||= ENV['RAILS_ENV'] || ENV['RACK_ENV'] || 'development'
    end

    def boot_system
      ENV['RACK_ENV'] = ENV['RAILS_ENV'] = detected_environment

      raise ArgumentError, "#{options[:require]} does not exist" unless File.exist?(options[:require])

      if File.directory?(options[:require])
        require 'rails'
        require 'creeper/rails'
        require File.expand_path("#{options[:require]}/config/environment.rb")
        ::Rails.application.eager_load!
      else
        require options[:require]
      end
    end

    def validate!
      options[:queues] << 'default' if options[:queues].empty?

      if !File.exist?(options[:require]) ||
         (File.directory?(options[:require]) && !File.exist?("#{options[:require]}/config/application.rb"))
        logger.info "=================================================================="
        logger.info "  Please point creeper to a Rails 3 application or a Ruby file    "
        logger.info "  to load your worker classes with -r [DIR|FILE]."
        logger.info "=================================================================="
        logger.info @parser
        die(1)
      end
    end

    def parse_options(argv)
      opts = {}

      @parser = OptionParser.new do |o|
        o.on "-q", "--queue QUEUE[,WEIGHT]...", "Queues to process with optional weights" do |arg|
          queues_and_weights = arg.scan(/(\w+),?(\d*)/)
          queues_and_weights.each {|queue_and_weight| parse_queues(opts, *queue_and_weight)}
          opts[:strict] = queues_and_weights.collect(&:last).none? {|weight| weight != ''}
        end

        o.on "-v", "--verbose", "Print more verbose output" do
          Creeper.logger.level = ::Logger::DEBUG
        end

        o.on '-e', '--environment ENV', "Application environment" do |arg|
          opts[:environment] = arg
        end

        o.on '-t', '--timeout NUM', "Shutdown timeout" do |arg|
          opts[:timeout] = arg.to_i
        end

        o.on '-r', '--require [PATH|DIR]', "Location of Rails application with workers or file to require" do |arg|
          opts[:require] = arg
        end

        o.on '-c', '--concurrency INT', "processor threads to use" do |arg|
          opts[:concurrency] = arg.to_i
        end

        o.on '-P', '--pidfile PATH', "path to pidfile" do |arg|
          opts[:pidfile] = arg
        end

        o.on '-C', '--config PATH', "path to YAML config file" do |arg|
          opts[:config_file] = arg
        end

        o.on '-V', '--version', "Print version and exit" do |arg|
          puts "Creeper #{Creeper::VERSION}"
          die(0)
        end
      end

      @parser.banner = "creeper [options]"
      @parser.on_tail "-h", "--help", "Show help" do
        logger.info @parser
        die 1
      end
      @parser.parse!(argv)
      opts
    end

    def write_pid
      if path = options[:pidfile]
        File.open(path, 'w') do |f|
          f.puts Process.pid
        end
      end
    end

    def parse_config(cli)
      opts = {}
      if cli[:config_file] && File.exist?(cli[:config_file])
        opts = YAML.load_file cli[:config_file]
        queues = opts.delete(:queues) || []
        queues.each { |name, weight| parse_queues(opts, name, weight) }
      end
      opts
    end

    def parse_queues(opts, q, weight)
      [weight.to_i, 1].max.times do
       (opts[:queues] ||= []) << q
      end
    end
  end
end

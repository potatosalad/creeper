require 'creeper/version'
require 'creeper/logging'
require 'creeper/client'
require 'creeper/worker'
require 'creeper/beanstalk_connection'
require 'creeper/redis_connection'
require 'creeper/util'

require 'creeper/legacy'

require 'creeper/extensions/action_mailer'
require 'creeper/extensions/active_record'
require 'creeper/rails' if defined?(::Rails::Engine)

require 'multi_json'

module Creeper

  extend Creeper::Legacy

  DEFAULTS = {
    :queues => [],
    :concurrency => 25,
    :require => '.',
    :environment => nil,
    :timeout => 8,
    :enable_rails_extensions => true,
  }

  def self.options
    @options ||= DEFAULTS.dup
  end

  def self.options=(opts)
    @options = opts
  end

  ##
  # Configuration for Creeper server, use like:
  #
  #   Creeper.configure_server do |config|
  #     config.redis = { :namespace => 'myapp', :size => 25, :url => 'redis://myhost:8877/mydb' }
  #     config.server_middleware do |chain|
  #       chain.add MyServerHook
  #     end
  #   end
  def self.configure_server
    yield self if server?
  end

  ##
  # Configuration for Creeper client, use like:
  #
  #   Creeper.configure_client do |config|
  #     config.redis = { :namespace => 'myapp', :size => 1, :url => 'redis://myhost:8877/mydb' }
  #   end
  def self.configure_client
    yield self unless server?
  end

  def self.server?
    defined?(Creeper::CLI)
  end

  def self.beanstalk(&block)
    if block_given?
      yield beanstalk
    else
      @beanstalk ||= Creeper::BeanstalkConnection.create
    end
  end

  def self.beanstalk=(hash)
    if @beanstalk
      @beanstalk.close rescue nil
    end
    if hash.is_a?(Hash)
      @beanstalk = BeanstalkConnection.create(hash)
    elsif hash.is_a?(Beanstalk::Pool)
      @beanstalk = hash
    else
      raise ArgumentError, "beanstalk= requires a Hash or Beanstalk::Pool"
    end
  end

  def self.redis(&block)
    @redis ||= Creeper::RedisConnection.create
    raise ArgumentError, "requires a block" if !block
    @redis.with(&block)
  end

  def self.redis=(hash)
    if hash.is_a?(Hash)
      @redis = RedisConnection.create(hash)
    elsif hash.is_a?(ConnectionPool)
      @redis = hash
    else
      raise ArgumentError, "redis= requires a Hash or ConnectionPool"
    end
  end

  def self.client_middleware
    @client_chain ||= Client.default_middleware
    yield @client_chain if block_given?
    @client_chain
  end

  def self.server_middleware
    @server_chain ||= Processor.default_middleware
    yield @server_chain if block_given?
    @server_chain
  end

  def self.server?
    defined?(Creeper::CLI)
  end

  def self.load_json(string)
    MultiJson.decode(string)
  end

  def self.dump_json(object)
    MultiJson.encode(object)
  end

  def self.logger
    Creeper::Logging.logger
  end

  def self.logger=(log)
    Creeper::Logging.logger = log
  end

  def self.poll_interval=(interval)
    self.options[:poll_interval] = interval
  end

end
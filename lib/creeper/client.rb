require 'creeper/legacy'
require 'creeper/middleware/chain'

module Creeper
  class Client

    def self.default_middleware
      Middleware::Chain.new do |m|
      end
    end

    def self.registered_workers
      Creeper.redis { |x| x.smembers('workers') }
    end

    def self.registered_queues
      Creeper.redis { |x| x.smembers('queues') }
    end

    ##
    # The main method used to push a job to Redis.  Accepts a number of options:
    #
    #   queue - the named queue to use, default 'default'
    #   class - the worker class to call, required
    #   args - an array of simple arguments to the perform method, must be JSON-serializable
    #   retry - whether to retry this job if it fails, true or false, default true
    #   backtrace - whether to save any error backtrace, default false
    #
    # All options must be strings, not symbols.  NB: because we are serializing to JSON, all
    # symbols in 'args' will be converted to strings.
    #
    # Returns nil if not pushed to Redis or a unique Job ID if pushed.
    #
    # Example:
    #   Creeper::Client.push('queue' => 'my_queue', 'class' => MyWorker, 'args' => ['foo', 1, :bat => 'bar'])
    #
    def self.push(item)
      raise(ArgumentError, "Message must be a Hash of the form: { 'class' => SomeWorker, 'args' => ['bob', 1, :foo => 'bar'] }") unless item.is_a?(Hash)
      raise(ArgumentError, "Message must include a class and set of arguments: #{item.inspect}") if !item['class'] || !item['args']
      raise(ArgumentError, "Message must include a Creeper::Worker class, not class name: #{item['class'].ancestors.inspect}") if !item['class'].is_a?(Class) || !item['class'].respond_to?('get_creeper_options')

      worker_class = item['class']
      item['class'] = item['class'].to_s

      item = worker_class.get_creeper_options.merge(item)
      # item['retry'] = !!item['retry']
      at          = item['at']
      queue       = item['queue']
      priority    = item['priority']
      delay       = item['delay']
      delay     ||= at.to_i - Time.now.to_i if at and at.respond_to?(:to_i)
      time_to_run = item['time_to_run']
      # item['jid'] = SecureRandom.base64

      pushed = false
      job = Creeper.client_middleware.invoke(worker_class, item, queue) do
        payload = Creeper.dump_json([ queue, item ])
        args    = [ payload, priority, delay, time_to_run ]
        args.pop while args.last.nil?
        Creeper.redis do |conn|
          conn.sadd('queues', queue)
        end
        Creeper.beanstalk do |beanstalk|
          beanstalk.on_tube(queue) do |conn|
            conn.put(*args)
          end
        end
        # Creeper.redis do |conn|
        #   if item['at']
        #     pushed = conn.zadd('schedule', item['at'].to_s, payload)
        #   else
        #     _, pushed = conn.multi do
        #       conn.sadd('queues', queue)
        #       conn.rpush("queue:#{queue}", payload)
        #     end
        #   end
        # end
      end
      pushed = !!job
      pushed ? job : nil
    end

    # Redis compatibility helper.  Example usage:
    #
    #   Creeper::Client.enqueue(MyWorker, 'foo', 1, :bat => 'bar')
    #
    # Messages are enqueued to the 'default' queue.
    #
    def self.enqueue(klass, *args)
      klass.perform_async(*args)
    end
  end
end

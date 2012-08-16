require 'spec_helper'
require 'creeper/client'
require 'creeper/worker'

describe Creeper::Client do

  context 'with mock beanstalk and redis' do
    before do
      @beanstalk  = double('beanstalk')
      @connection = double('connection')
      def @beanstalk.on_tube(tube); yield @connection if block_given?; end
      Creeper.instance_variable_set(:@beanstalk, @beanstalk)
      @redis = double('redis')
      def @redis.multi; [yield] * 2 if block_given?; end
      def @redis.set(*); true; end
      def @redis.sadd(*); true; end
      def @redis.srem(*); true; end
      def @redis.get(*); nil; end
      def @redis.del(*); nil; end
      def @redis.incrby(*); nil; end
      def @redis.setex(*); true; end
      def @redis.expire(*); true; end
      def @redis.watch(*); true; end
      def @redis.with_connection; yield self; end
      def @redis.with; yield self; end
      def @redis.exec; true; end
      Creeper.instance_variable_set(:@redis, @redis)
    end

    after do
      Creeper.instance_variable_set(:@beanstalk, nil)
      Creeper.instance_variable_set(:@redis, nil)
    end

    it 'raises ArgumentError with invalid params' do
      expect do
        Creeper::Client.push('foo', 1)
      end.to raise_error(ArgumentError)

      expect do
        Creeper::Client.push('foo', :class => 'Foo', :noargs => [1, 2])
      end.to raise_error(ArgumentError)
    end

    it 'pushes messages to beanstalk' do
      @beanstalk.should_receive(:on_tube).with('foo').and_yield(@connection)
      @connection.should_receive(:put).with(%q(["foo",{"retry":true,"queue":"foo","class":"MyWorker","args":[1,2]}])).and_return(24)
      pushed = Creeper::Client.push('queue' => 'foo', 'class' => MyWorker, 'args' => [1, 2])
      expect(pushed).to eq(24)
    end

    it 'has default options' do
      expect(Creeper::Worker::ClassMethods::DEFAULT_OPTIONS).to eq(MyWorker.get_creeper_options)
    end

    it 'handles perform_async' do
      @beanstalk.should_receive(:on_tube).with('default').and_yield(@connection)
      @connection.should_receive(:put).with(%q(["default",{"retry":true,"queue":"default","class":"MyWorker","args":[1,2]}])).and_return(24)
      pushed = MyWorker.perform_async(1, 2)
      expect(pushed).to eq(24)
    end

    it 'handles perform_async on failure' do
      @beanstalk.should_receive(:on_tube).with('default').and_yield(@connection)
      @connection.should_receive(:put).with(%q(["default",{"retry":true,"queue":"default","class":"MyWorker","args":[1,2]}])).and_return(nil)
      pushed = MyWorker.perform_async(1, 2)
      expect(pushed).to be_nil
    end

    it 'enqueues messages to beanstalk' do
      @beanstalk.should_receive(:on_tube).with('default').and_yield(@connection)
      @connection.should_receive(:put).with(%q(["default",{"retry":true,"queue":"default","class":"MyWorker","args":[1,2]}])).and_return(24)
      pushed = Creeper::Client.enqueue(MyWorker, 1, 2)
      expect(pushed).to eq(24)
    end

    it 'enqueues messages to beanstalk using legacy method' do
      @beanstalk.should_receive(:on_tube).with('my.worker').and_yield(@connection)
      @connection.should_receive(:put).with(%q(["my.worker",{"retry":true,"queue":"my.worker","args":[1,2],"class":"MyWorker","delay":0,"priority":65536,"time_to_run":120}]), 65536, 0, 120).and_return(24)
      pushed = Creeper.enqueue('my.worker', 1, 2)
      expect(pushed).to eq(24)
    end

    it 'enqueues to the named queue' do
      @beanstalk.should_receive(:on_tube).with(:flimflam).and_yield(@connection)
      @connection.should_receive(:put).with(%q(["flimflam",{"retry":true,"queue":"flimflam","timeout":1,"class":"QueuedWorker","args":[1,2]}])).and_return(24)
      pushed = QueuedWorker.perform_async(1, 2)
      expect(pushed).to eq(24)
    end

    it 'retrieves queues' do
      @redis.should_receive(:smembers).with('queues').and_return(['bob'])
      expect(Creeper::Client.registered_queues).to eq(['bob'])
    end

    it 'retrieves workers' do
      @redis.should_receive(:smembers).with('workers').and_return(['bob'])
      expect(Creeper::Client.registered_workers).to eq(['bob'])
    end

  end

  describe 'inheritance' do
    it 'should inherit creeper options' do
      expect(AWorker.get_creeper_options['retry']).to eq('base')
      expect(BWorker.get_creeper_options['retry']).to eq('b')
    end
  end

end

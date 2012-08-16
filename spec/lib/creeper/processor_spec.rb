require 'spec_helper'
require 'creeper/processor'

describe Creeper::Processor do

  context 'with mock setup' do

    before do
      stub_const('TestException', Class.new(StandardError))
      stub_const('TEST_EXCEPTION', TestException.new("kerboom!"))
    end

    let(:boss)      { double('boss') }
    let(:processor) { ::Creeper::Processor.new(boss) }

    let(:job)  { double('job') }
    let(:conn) { double('conn') }

    before do
      $invokes = 0
      Celluloid.logger = nil
      Creeper.redis = REDIS
    end

    class MockWorker
      include Creeper::Worker
      def perform(args)
        raise TEST_EXCEPTION if args == 'boom'
        args.pop if args.is_a? Array
        $invokes += 1
      end
    end

    it 'processes as expected' do
      msg = Creeper.dump_json({ 'class' => MockWorker.to_s, 'args' => ['myarg'] })

      conn.should_receive(:close).and_return(true)
      job.should_receive(:delete).and_return(true)
      boss.should_receive(:processor_done!).with(processor).and_return(nil)

      processor.process(msg, 'default', job, conn)
      expect($invokes).to eq(1)
    end

    it 'passes exceptions to ExceptionHandler' do
      msg = Creeper.dump_json({ 'class' => MockWorker.to_s, 'args' => ['boom'] })

      conn.should_receive(:close).and_return(true)
      job.should_receive(:bury).and_return(true)

      expect do
        processor.process(msg, 'default', job, conn)
      end.to raise_error(TestException)

      expect($invokes).to eq(0)
    end

    it 're-raises exceptions after handling' do
      msg = Creeper.dump_json({ 'class' => MockWorker.to_s, 'args' => ['boom'] })
      re_raise = false

      conn.should_receive(:close).and_return(true)
      job.should_receive(:bury).and_return(true)

      begin
        processor.process(msg, 'default', job, conn)
      rescue TestException
        re_raise = true
      end

      expect(re_raise).to be_true # does not re-raise exceptions after handling
    end

    it 'does not modify original arguments' do
      msg = { 'class' => MockWorker.to_s, 'args' => [['myarg']] }
      msgstr = Creeper.dump_json(msg)

      conn.should_receive(:close).and_return(true)
      job.should_receive(:delete).and_return(true)
      boss.should_receive(:processor_done!).with(processor).and_return(nil)

      processor.process(msgstr, 'default', job, conn)
      expect(msg['args']).to eq([['myarg']])
    end

  end

end

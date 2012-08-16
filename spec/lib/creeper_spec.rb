require 'spec_helper'
require 'creeper/cli'

describe Creeper do

  it 'is able to process a real job' do
    pending 'still need to figure out how to test the daemon'
    let(:cli) { Creeper::CLI.instance }

    before do
      $rd, $wr = IO.pipe
      $rd.sync, $wr.sync = true
      if @pid = fork
        # parent
        $wr.close
      else
        # child
        $rd.close
        cli.parse(['creeper', '-r', './spec/support/fake_env.rb'])
        sleep 5
        begin
          cli.run
        rescue SystemExit
          Process.kill(:KILL, $$)
        end
      end
    end

    after do
      if @pid
        Process.kill(:TERM, @pid)
        done = nil
        # 8.times do
        #   begin
        #     Process.getpgid(@pid)
        #   rescue Errno::ESRCH
        #     done = true
        #     break
        #   end
        #   sleep 1
        # end
        # expect(done).to be_true
        sleep 1
        Process.kill(:KILL, @pid)
        child_pid, status = Process.waitpid2(-1, Process::WNOHANG)
        expect(child_pid).to eq(@pid)
        # expect(status).to be_success

        $rd.close rescue nil
        $wr.close rescue nil
      end
    end

    it 'is able to process a real job' do
      pending 'still need to figure out how to test the daemon'
      RealWorker.perform_async(1, 2)
      result = nil
      Timeout::timeout(10) do
        result = $rd.read
      end
      expect(result).to eq('[1,2]')
    end
  end

end
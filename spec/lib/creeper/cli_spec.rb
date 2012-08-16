require 'spec_helper'
require 'creeper/cli'
require 'tempfile'

describe Creeper::CLI do

  cli = Creeper::CLI.instance
  def cli.die(code)
    @code = code
  end

  def cli.valid?
    !@code
  end

  context 'with cli' do

    let(:cli) { Creeper::CLI.instance }

    it 'blows up with an invalid require' do
      expect do
        cli.parse(['creeper', '-r', 'foobar'])
      end.to raise_error(ArgumentError)
    end

    it 'requires the specified Ruby code' do
      cli.parse(['creeper', '-r', './spec/support/fake_env.rb'])
      expect($LOADED_FEATURES.any? { |x| x =~ /fake_env/ }).to be_true
      expect(cli).to be_valid
    end

    it 'changes concurrency' do
      cli.parse(['creeper', '-c', '60', '-r', './spec/support/fake_env.rb'])
      expect(Creeper.options[:concurrency]).to eq(60)
    end

    it 'changes queues' do
      cli.parse(['creeper', '-q', 'foo', '-r', './spec/support/fake_env.rb'])
      expect(Creeper.options[:queues]).to eq(['foo'])
    end

    it 'sets strictly ordered queues if weights are not present' do
      cli.parse(['creeper', '-q', 'foo,bar', '-r', './spec/support/fake_env.rb'])
      expect(!!Creeper.options[:strict]).to be_true
    end

    it 'does not set strictly ordered queues if weights are present' do
      cli.parse(['creeper', '-q', 'foo,3', '-r', './spec/support/fake_env.rb'])
      expect(!!Creeper.options[:strict]).to be_false
    end

    it 'changes timeout' do
      cli.parse(['creeper', '-t', '30', '-r', './spec/support/fake_env.rb'])
      expect(Creeper.options[:timeout]).to eq(30)
    end

    it 'handles multiple queues with weights with multiple switches' do
      cli.parse(['creeper', '-q', 'foo,3', '-q', 'bar', '-r', './spec/support/fake_env.rb'])
      expect(Creeper.options[:queues]).to eq(%w(foo foo foo bar))
    end

    it 'handles multiple queues with weights with a single switch' do
      cli.parse(['creeper', '-q', 'bar,foo,3', '-r', './spec/support/fake_env.rb'])
      expect(Creeper.options[:queues]).to eq(%w(bar foo foo foo))
    end

    it 'sets verbose' do
      old = Creeper.logger.level
      cli.parse(['creeper', '-v', '-r', './spec/support/fake_env.rb'])
      expect(Creeper.logger.level).to eq(Logger::DEBUG)
      # If we leave the logger at DEBUG it'll add a lot of noise to the test output
      Creeper.logger.level = old
    end

    context 'with pidfile' do

      let(:tmp_file) { Tempfile.new('creeper-test') }
      let(:tmp_path) { tmp_file.path.tap { tmp_file.close! } }

      before do
        cli.parse(['creeper', '-P', tmp_path, '-r', './spec/support/fake_env.rb'])
      end

      after do
        File.unlink tmp_path if File.exist? tmp_path
      end

      it 'sets pidfile path' do
        expect(Creeper.options[:pidfile]).to eq(tmp_path)
      end

      it 'writes pidfile' do
        expect(Process.pid).to eq(File.read(tmp_path).strip.to_i)
      end

    end

    context 'with config file' do

      before do
        cli.parse(['creeper', '-C', './spec/support/config.yml'])
      end

      it 'takes a path' do
        expect(Creeper.options[:config_file]).to eq('./spec/support/config.yml')
      end

      it 'sets verbose' do
        expect(Creeper.options[:verbose]).to_not be_true
      end

      it 'sets require file' do
        expect(Creeper.options[:require]).to eq('./spec/support/fake_env.rb')
      end

      it 'sets environment' do
        expect(Creeper.options[:environment]).to eq('xzibit')
      end

      it 'sets concurrency' do
        expect(Creeper.options[:concurrency]).to eq(50)
      end

      it 'sets pid file' do
        expect(Creeper.options[:pidfile]).to eq('/tmp/creeper-config-test.pid')
      end

      it 'sets queues' do
        expect(Creeper.options[:queues].count { |q| q == 'often'  }).to eq(2)
        expect(Creeper.options[:queues].count { |q| q == 'seldom' }).to eq(1)
      end
    end

    context 'with config file and flags' do

      let(:tmp_lib_path) { '/tmp/require-me.rb' }
      let(:tmp_file)     { Tempfile.new('creeperr') }
      let(:tmp_path)     { tmp_file.path.tap { tmp_file.close! } }

      before do
        # We need an actual file here.
        File.open(tmp_lib_path, 'w') do |f|
          f.puts "# do work"
        end

        cli.parse(['creeper',
                   '-C', './spec/support/config.yml',
                   '-e', 'snoop',
                   '-c', '100',
                   '-r', tmp_lib_path,
                   '-P', tmp_path,
                   '-q', 'often,7',
                   '-q', 'seldom,3'])
      end

      after do
        File.unlink tmp_lib_path if File.exist? tmp_lib_path
        File.unlink tmp_path if File.exist? tmp_path
      end

      it 'uses concurrency flag' do
        expect(Creeper.options[:concurrency]).to eq(100)
      end

      it 'uses require file flag' do
        expect(Creeper.options[:require]).to eq(tmp_lib_path)
      end

      it 'uses environment flag' do
        expect(Creeper.options[:environment]).to eq('snoop')
      end

      it 'uses pidfile flag' do
        expect(Creeper.options[:pidfile]).to eq(tmp_path)
      end

      it 'sets queues' do
        expect(Creeper.options[:queues].count { |q| q == 'often' }).to  eq(7)
        expect(Creeper.options[:queues].count { |q| q == 'seldom' }).to eq(3)
      end
    end

    describe 'Creeper::CLI#parse_queues' do
      describe 'when weight is present' do
        it 'concatenates queue to opts[:queues] weight number of times' do
          opts = {}
          cli.send :parse_queues, opts, 'often', 7
          expect(opts[:queues]).to eq(%w[often] * 7)
        end
      end

      describe 'when weight is not present' do
        it 'concatenates queue to opts[:queues] once' do
          opts = {}
          cli.send :parse_queues, opts, 'once', nil
          expect(opts[:queues]).to eq(%w[once])
        end
      end
    end

  end

end

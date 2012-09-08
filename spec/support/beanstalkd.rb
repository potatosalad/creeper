require 'fileutils'

ENV['BEANSTALK_URL'] ||= 'beanstalk://127.0.0.1:11313/'

$beanstalkd_pid      = nil
$beanstalkd_data_dir = File.expand_path('../../../tmp/data', __FILE__)

def attempt_beanstalk_connection!
  Creeper.beanstalk = { url: ENV['BEANSTALK_URL'] }
end

RSpec.configure do |config|
  config.before(:suite) do
    begin
      attempt_beanstalk_connection!
    rescue Beanstalk::NotConnected
      FileUtils.mkpath($beanstalkd_data_dir)
      $beanstalkd_pid = Process.spawn('beanstalkd', '-b', $beanstalkd_data_dir, '-p', '11313')

      retries = 1

      begin
        sleep (retries * 0.1)
        attempt_beanstalk_connection!
      rescue Beanstalk::NotConnected => e
        retries -= 1
        retry if retries > 5
        raise e
      end
    end
  end

  config.after(:suite) do
    if $beanstalkd_pid
      Process.kill(:SIGINT, $beanstalkd_pid)
      Process.waitpid2($beanstalkd_pid)

      FileUtils.rmtree($beanstalkd_data_dir) if File.directory?($beanstalkd_data_dir)
    end
  end
end
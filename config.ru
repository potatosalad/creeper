require 'creeper'

Creeper.configure_client do |config|
  config.redis = { :size => 1 }
end

#Creeper.redis {|conn| conn.flushdb }
#10.times do |idx|
  #Creeper::Client.push('class' => 'HardWorker', 'args' => ['foo', 0.1, idx])
#end

#Creeper.redis { |conn| conn.zadd('retry', Time.now.utc.to_f + 3000, MultiJson.encode({
  #'class' => 'HardWorker', 'args' => ['foo', 0.1, Time.now.to_f],
  #'queue' => 'default', 'error_message' => 'No such method', 'error_class' => 'NoMethodError',
  #'failed_at' => Time.now.utc, 'retry_count' => 0 })) }

require 'creeper/web'
run Creeper::Web

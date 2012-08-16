class SuicidalWorker
  include Creeper::Worker
  creeper_legacy_queue 'suicidal.worker'
  creeper_options 'timeout' => 60, 'backtrace' => 5, 'queue' => 'suicidal.worker'

  def perform(name, count, salt)
    raise name if name == 'crash'
    logger.info Time.now
    (1..count).each do |i|
      feeling_lazy = (rand(0..1) == 0)
      if i % 2 == 0
        HardWorker.perform_async(name, (i > 10) ? rand(0..10) : i, salt)
      elsif i % 3 == 0
        if feeling_lazy
          LazyWorker.perform_async('crash', (i > 10) ? rand(0..10) : i, salt)
        else
          i.times do
            FastWorker.perform_async('crash', (i > 10) ? rand(0..10) : i, salt)
          end
        end
      else
        if feeling_lazy
          LazyWorker.perform_async(name, (i > 10) ? rand(0..10) : i, salt)
        else
          i.times do
            FastWorker.perform_async(name, i, salt)
          end
        end
      end
    end
    sleep rand(0..5)
  end
end

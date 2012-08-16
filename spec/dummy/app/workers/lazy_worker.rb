class LazyWorker
  include Creeper::Worker
  creeper_legacy_queue 'lazy.worker'
  creeper_options 'timeout' => 20, 'backtrace' => 5, 'queue' => 'lazy.worker'

  def perform(name, count, salt)
    logger.info Time.now
    sleep count
    # too lazy...we'll let the hard worker do it
    HardWorker.perform_async(name, count, salt)
  end
end

class FastWorker
  include Creeper::Worker
  creeper_legacy_queue 'fast.worker'
  creeper_options 'timeout' => 20, 'backtrace' => 5, 'queue' => 'fast.worker', 'retry' => false

  def perform(name, count, salt)
    raise name if name == 'crash'
    logger.info Time.now
  end
end

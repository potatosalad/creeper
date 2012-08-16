class HardWorker
  include Creeper::Worker
  creeper_legacy_queue 'hard.worker'
  creeper_options 'timeout' => 20, 'backtrace' => 5

  def perform(name, count, salt)
    raise name if name == 'crash'
    logger.info Time.now
    sleep count
  end
end

class QueuedWorker
  include Creeper::Worker
  creeper_legacy_queue 'queued.worker'
  creeper_options :queue => :flimflam, :timeout => 1
end
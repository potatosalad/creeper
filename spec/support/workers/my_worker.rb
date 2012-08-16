class MyWorker
  include Creeper::Worker
  creeper_legacy_queue 'my.worker'
end
class BaseWorker
  include Creeper::Worker
  creeper_options 'retry' => 'base'
end

class AWorker < BaseWorker
end

class BWorker < BaseWorker
  creeper_options 'retry' => 'b'
end
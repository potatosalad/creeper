class RealWorker
  include Creeper::Worker

  def perform(*args)
    if $wr
      $wr.syswrite(Creeper.dump_json(args))
      $wr = $wr.close rescue nil
    end
  end
end
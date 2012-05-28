module Celluloid
  class Actor

    def handle_crash(exception)
      prefix = (@subject.respond_to?(:prefix) rescue nil) ? ("#{@subject.prefix} " rescue nil) : nil
      Logger.crash("#{prefix}#{@subject.class} crashed!", exception)
      shutdown ExitEvent.new(@proxy, exception)
    rescue => ex
      Logger.crash("#{@subject.class}: ERROR HANDLER CRASHED!", ex)
    end

  end
end

module Celluloid
  class PoolManager

    # ensure that the provisioned worker is alive to prevent PoolManager from dying
    alias :original_provision_worker :provision_worker
    def provision_worker
      if (worker = original_provision_worker).alive?
        return worker
      end
      until worker.alive?
        worker = original_provision_worker
      end
      worker
    end

    def crash_handler(actor, reason)
      return unless reason # don't restart workers that exit cleanly
      index = @idle.rindex(actor) # replace the old actor if possible
      if index
        @idle[index] = @worker_class.new_link(*@args)
      else
        @idle << @worker_class.new_link(*@args)
      end
    end

  end
end
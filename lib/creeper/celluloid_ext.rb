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
    def execute(method, *args, &block)
      worker = provision_worker
      
      begin
        worker._send_ method, *args, &block
      rescue Celluloid::DeadActorError, Celluloid::MailboxError
        execute(method, *args, &block)
      ensure
        @idle << worker if worker && worker.alive?
      end
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
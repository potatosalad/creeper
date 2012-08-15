module Creeper
  module ExceptionHandler

    def handle_exception(ex, msg)
      Creeper.logger.warn msg
      Creeper.logger.warn ex
      Creeper.logger.warn ex.backtrace.join("\n")
      send_to_airbrake(msg, ex) if defined?(::Airbrake)
      send_to_exceptional(msg, ex) if defined?(::Exceptional)
      send_to_exception_notifier(msg, ex) if defined?(::ExceptionNotifier)
    end

    private

    def send_to_airbrake(msg, ex)
      ::Airbrake.notify(ex, :parameters => msg)
    end

    def send_to_exceptional(msg, ex)
      if ::Exceptional::Config.should_send_to_api?
        ::Exceptional.context(msg)
        ::Exceptional::Remote.error(::Exceptional::ExceptionData.new(ex))
      end
    end

    def send_to_exception_notifier(msg, ex)
      ::ExceptionNotifier::Notifier.background_exception_notification(ex, :data => { :message => msg })
    end
  end
end

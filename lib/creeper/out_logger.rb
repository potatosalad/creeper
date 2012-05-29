module Creeper
  module OutLogger

    extend self

    # Send a debug message
    def debug(string)
      Creeper.out_logger.debug(string) if Creeper.out_logger
    end

    # Send a info message
    def info(string)
      Creeper.out_logger.info(string) if Creeper.out_logger
    end

    # Send a warning message
    def warn(string)
      Creeper.out_logger.warn(string) if Creeper.out_logger
    end

    # Send an error message
    def error(string)
      Creeper.out_logger.error(string) if Creeper.out_logger
    end

    # Handle a crash
    def crash(string, exception)
      string << "\n" << format_exception(exception)
      error string
    end

    # Format an exception message
    def format_exception(exception)
      str = "#{exception.class}: #{exception.to_s}\n"
      str << exception.backtrace.join("\n")
    end

  end
end
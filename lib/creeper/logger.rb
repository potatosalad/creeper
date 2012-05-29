module Creeper
  module Logger
    module_function

    # Send a debug message
    def debug(string)
      Creeper.logger.debug(string) if Creeper.logger
    end

    # Send a info message
    def info(string)
      Creeper.logger.info(string) if Creeper.logger
    end

    # Send a warning message
    def warn(string)
      Creeper.logger.warn(string) if Creeper.logger
    end

    # Send an error message
    def error(string)
      Creeper.error_logger.error(string) if Creeper.error_logger
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
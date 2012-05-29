module Creeper
  module ErrLogger
    module_function

    # Send a debug message
    def debug(string)
      Creeper.err_logger.debug(string) if Creeper.err_logger
    end

    # Send a info message
    def info(string)
      Creeper.err_logger.info(string) if Creeper.err_logger
    end

    # Send a warning message
    def warn(string)
      Creeper.err_logger.warn(string) if Creeper.err_logger
    end

    # Send an error message
    def error(string)
      Creeper.err_logger.error(string) if Creeper.err_logger
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
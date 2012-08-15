require 'creeper/exception_handler'

module Creeper
  ##
  # This module is part of Creeper core and not intended for extensions.
  #
  module Util
    include ExceptionHandler

    EXPIRY = 60 * 60

    def constantize(camel_cased_word)
      names = camel_cased_word.split('::')
      names.shift if names.empty? || names.first.empty?

      constant = Object
      names.each do |name|
        constant = constant.const_defined?(name) ? constant.const_get(name) : constant.const_missing(name)
      end
      constant
    end

    def watchdog(last_words)
      yield
    rescue => ex
      handle_exception(ex, { :context => last_words })
    end

    def logger
      Creeper.logger
    end

    def beanstalk(&block)
      Creeper.beanstalk(&block)
    end

    def redis(&block)
      Creeper.redis(&block)
    end

    def process_id
      Process.pid
    end
  end
end

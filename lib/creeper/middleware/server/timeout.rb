require 'timeout'

module Creeper
  module Middleware
    module Server
      class Timeout

        def call(worker, msg, queue, job, conn)
          if msg['timeout'] && msg['timeout'].to_i != 0
            ::Timeout.timeout(msg['timeout'].to_i) do
              yield
            end
          else
            yield
          end
        end

      end
    end
  end
end

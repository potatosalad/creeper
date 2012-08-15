module Creeper
  module Middleware
    module Server
      class Logging

        def call(*args)
          Creeper::Logging.with_context("#{args[0].class.to_s} MSG-#{args[0].object_id.to_s(36)}") do
            begin
              start = Time.now
              logger.info { "start" }
              yield
              logger.info { "done: #{elapsed(start)} sec" }
            rescue
              logger.info { "fail: #{elapsed(start)} sec" }
              raise
            end
          end
        end

        def elapsed(start)
          (Time.now - start).to_f.round(3)
        end

        def logger
          Creeper.logger
        end
      end
    end
  end
end


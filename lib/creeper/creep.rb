module Creeper
  module Creep

    def enqueue(job, data = {}, options = {})
      Creeper.enqueue(job, data, options)
    end

    def job(name, &block)
      Creeper.job(name, &block)
    end

    def before(name = nil, &block)
      Creeper.before(name, &block)
    end

    def after(name = nil, &block)
      Creeper.after(name, &block)
    end

    def error(name = nil, &block)
      Creeper.error(name, &block)
    end

  end
end
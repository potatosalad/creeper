module Creeper
  module Creep

    def clear!
      Creeper.default_session.disconnect if Creeper.instance_variable_defined?(:@default_session) and Creeper.instance_variable_get(:@default_session)
      Creeper.instance_variable_set(:@default_session, nil)
    end

    def default_session
      return Creeper.instance_variable_get(:@default_session) if Creeper.instance_variable_defined?(:@default_session)
      Creeper.instance_variable_set(:@default_session, Creeper::Session.new)
    end

    def enqueue(job, args = {}, opts = {})
      default_session.enqueue(job, args, opts)
    end

    def job(name, &block)
      default_session.job(name, &block)
    end

    def before(&block)
      default_session.before(&block)
    end

    def error(&block)
      default_session.error(&block)
    end

  end
end
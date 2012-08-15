module Creeper
  def self.hook_rails!
    return unless Creeper.options[:enable_rails_extensions]
    if defined?(ActiveRecord)
      ActiveRecord::Base.extend(Creeper::Extensions::ActiveRecord)
      ActiveRecord::Base.send(:include, Creeper::Extensions::ActiveRecord)
    end

    if defined?(ActionMailer)
      ActionMailer::Base.extend(Creeper::Extensions::ActionMailer)
    end
  end

  class Rails < ::Rails::Engine
    config.autoload_paths << File.expand_path("#{config.root}/app/workers") if File.exist?("#{config.root}/app/workers")

    initializer 'creeper' do
      Creeper.hook_rails!
    end
  end if defined?(::Rails)
end

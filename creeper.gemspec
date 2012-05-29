# -*- encoding: utf-8 -*-
require File.expand_path('../lib/creeper/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Lyon Hill", "Andrew Bennett"]
  gem.email         = ["lyondhill@gmail.com", "potatosaladx@gmail.com"]
  gem.description   = %q{Creeper is an evented version of Stalker}
  gem.summary       = %q{A better solution for io bound jobs, same as stalker in functionality but more evented}
  gem.homepage      = "https://github.com/potatosalad/creeper"

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "creeper"
  gem.require_paths = ["lib"]
  gem.version       = Creeper::VERSION

  gem.add_development_dependency 'pry'
  gem.add_development_dependency 'rake'
  gem.add_development_dependency 'rspec'

  gem.add_dependency 'beanstalk-client'
  gem.add_dependency 'celluloid'
  gem.add_dependency 'kgio'
end

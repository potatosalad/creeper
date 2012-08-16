# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'creeper/version'

Gem::Specification.new do |gem|
  gem.name          = "creeper"
  gem.version       = Creeper::VERSION
  gem.authors       = ["Lyon Hill", "Andrew Bennett"]
  gem.email         = ["lyondhill@gmail.com", "potatosaladx@gmail.com"]
  gem.description   = %q{Creeper is an evented version of Stalker}
  gem.summary       = %q{A better solution for io bound jobs, same as stalker in functionality but more evented}
  gem.homepage      = "https://github.com/potatosalad/creeper"

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) } + ['creeperctl']
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]

  gem.add_dependency 'redis', '~> 3'
  gem.add_dependency 'redis-namespace'
  gem.add_dependency 'beanstalk-client'
  gem.add_dependency 'connection_pool', '~> 0.9.2'
  gem.add_dependency 'celluloid',  '~> 0.11.1'
  gem.add_dependency 'kgio'
  gem.add_dependency 'multi_json', '~> 1'

  gem.add_development_dependency 'pry'
  gem.add_development_dependency 'rake'
  gem.add_development_dependency 'rspec'
  gem.add_development_dependency 'actionmailer', '~> 3'
  gem.add_development_dependency 'activerecord', '~> 3'
end

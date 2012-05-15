# -*- encoding: utf-8 -*-
require File.expand_path('../lib/creeper/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["lyon"]
  gem.email         = ["lyondhill@gmail.com"]
  gem.description   = %q{Stalker with threads}
  gem.summary       = %q{A better solution for io bound jobs, same as stalker in functionality but more threadie.}
  gem.homepage      = "https://github.com/lyondhill/creeper"

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "creeper"
  gem.require_paths = ["lib"]
  gem.version       = Creeper::VERSION

  gem.add_development_dependency 'pry'
  gem.add_development_dependency 'rspec'
  # gem.add_development_dependency 'stalker'

  gem.add_dependency 'beanstalk-client'
  gem.add_dependency 'kgio'

end


source 'https://rubygems.org'

# Specify your gem's dependencies in creeper.gemspec
gemspec

gem 'rails', '3.2.8'

gem 'slim'
gem 'sprockets'
gem 'sass'

group :test do
  ## guard ##
  gem 'coolline'
  gem 'guard'
  gem 'guard-rspec'
  gem 'guard-spork'

  gem 'growl',             require: !!(RUBY_PLATFORM =~ /darwin/i) ? 'growl'     : false
  gem 'libnotify',         require: !!(RUBY_PLATFORM =~ /linux/i)  ? 'libnotify' : false
  gem 'terminal-notifier', require: !!(RUBY_PLATFORM =~ /darwin/i) ? 'growl'     : false
end
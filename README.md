# Creeper

Can be used as an in place drop in for stalker but it is multi threaded so you can easily do more without using more memory

*Note*: Creeper requires Ruby 1.9

Creeper - an improvement on Stalker
===================================

The big difference is how you "work" jobs

all you need is a runner (thread) count argument :)

```
Creeper.work([<job>, ...], <runner_count>)
```

[Beanstalkd](http://kr.github.com/beanstalkd/) is a fast, lightweight queueing backend inspired by mmemcached.

Queueing jobs
-------------

From anywhere in your app:

```ruby
require 'creeper'

Creeper.enqueue('email.send', :to => 'joe@example.com')
Creeper.enqueue('post.cleanup.all')
Creeper.enqueue('post.cleanup', :id => post.id)
```

Working jobs
------------

In a standalone file, typically jobs.rb or worker.rb:

```ruby
require 'creeper'
include Creeper::Creep

job 'email.send' do |args|
  Pony.send(:to => args['to'], :subject => "Hello there")
end

job 'post.cleanup.all' do |args|
  Post.all.each do |post|
    enqueue('post.cleanup', :id => post.id)
  end
end

job 'post.cleanup' do |args|
  Post.find(args['id']).cleanup
end

# All of these Creeper.work calls are equivalent:

Creeper.work(:all, 3)                                                 # work all jobs, 3 threads
Creeper.work(nil, 3)                                                  # same as previous line
Creeper.work([ 'email.send', 'post.cleanup.all', 'post.cleanup' ], 3) # same as previous line

# Here we work just one job:
Creeper.work('email.send', 5) # work 'email.send', 5 threads
```

Running
-------

First, make sure you have Beanstalkd installed and running:

```bash
$ sudo brew install beanstalkd
$ beanstalkd
```

Creeper:

```bash
$ sudo gem install creeper
```

Error Handling
-------------

If you include an `error` block in your jobs definition, that block will be invoked when a worker encounters an error. You might use this to report errors to an external monitoring service:

```ruby
error do |e, job, args|
  Exceptional.handle(e)
end
```

Before filter
-------------

If you wish to run a block of code prior to any job:

```ruby
before do |job|
  puts "About to work #{job}"
end
```
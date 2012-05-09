# Creeper

Can be used as an in place drop in for stalker but it is multi threaded so you can easily do more without using more memory

Creeper - an improvement on Stalker
==========================================

The big difference is how you "work" jobs

all you need is a thread count arguement :)
Creeper.work(<jobs>, <thread_count>)

[Beanstalkd](http://kr.github.com/beanstalkd/) is a fast, lightweight queueing backend inspired by mmemcached.

Queueing jobs
-------------

From anywhere in your app:

    require 'creeper'

    Creeper.enqueue('email.send', :to => 'joe@example.com')
    Creeper.enqueue('post.cleanup.all')
    Creeper.enqueue('post.cleanup', :id => post.id)

Working jobs
------------

In a standalone file, typically jobs.rb or worker.rb:

    require 'creeper'
    include Creeper

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
    
    Creeper.work(<jobs>, <thread_count>)

Running
-------

First, make sure you have Beanstalkd installed and running:

    $ sudo brew install beanstalkd
    $ beanstalkd

Creeper:

    $ sudo gem install creeper

Error Handling
-------------

If you include an `error` block in your jobs definition, that block will be invoked when a worker encounters an error. You might use this to report errors to an external monitoring service:

    error do |e, job, args|
      Exceptional.handle(e)
    end

Before filter
-------------

If you wish to run a block of code prior to any job:

    before do |job|
      puts "About to work #{job}"
    end

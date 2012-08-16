class WorkController < ApplicationController
  def index
    @count = rand(100)
    puts "Adding #{@count} jobs"
    @count.times do |x|
      HardWorker.perform_async('bubba', 0.01, x)
    end
  end

  def email
    UserMailer.delay_for(30.seconds).greetings(Time.now)
    render :nothing => true
  end

  def long
    50.times do |x|
      HardWorker.perform_async('bob', 10, x)
    end
    render :text => 'enqueued'
  end

  def crash
    HardWorker.perform_async('crash', 1, Time.now.to_f)
    render :text => 'enqueued'
  end

  def delayed_post
    p = Post.first
    unless p
      p = Post.create!(:title => "Title!", :body => 'Body!')
      p2 = Post.create!(:title => "Other!", :body => 'Second Body!')
    else
      p2 = Post.offset(1).first
    end
    p.delay.long_method(p2)
    render :nothing => true
  end

  def suicide
    @count = rand(1..5)
    @count.times do |x|
      SuicidalWorker.perform_async('billy', 100, x)
    end
    render text: "Adding #{@count} jobs"
  end

  def fast
    @count = rand(1000..10000)
    @count.times do |x|
      if x % 3 == 0
        FastWorker.perform_async('crash', 0, x)
      else
        FastWorker.perform_async('jack', 0, x)
      end
    end
    render text: "Adding #{@count} fast jobs"
  end

  def slow
    @count = rand(1000..10000)
    @count.times do |x|
      if x % 3 == 0
        HardWorker.perform_async('crash', 0, x)
      else
        HardWorker.perform_async('jack', rand(0..5), x)
      end
    end
    render text: "Adding #{@count} slow jobs"
  end

end

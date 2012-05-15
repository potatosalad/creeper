require 'spec_helper'

describe Creeper do

  after :each do
    Creeper.clear!
  end
  
  it "work a job and do it up" do
    val = rand(999999)
    Creeper.job('my.job') { |args| $result = args['val'] }
    Creeper.enqueue('my.job', :val => val)
    w = Creeper::Worker.new
    w.stub(:exception_message)
    w.stub(:log)
    w.prepare
    w.work_one_job
    val.should == $result
  end

  it "invoke error handler when defined" do
    with_an_error_handler
    Creeper.job('my.job') { |args| fail }
    Creeper.enqueue('my.job', :foo => 123)
    w = Creeper::Worker.new
    w.stub(:exception_message)
    w.stub(:log)
    w.prepare
    w.work_one_job
    $handled.should_not == nil
    'my.job'.should == $job_name
    {'foo' => 123}.should ==  $job_args
  end

  it "should be compatible with legacy error handlers" do
    exception = StandardError.new("Oh my, the job has failed!")
    Creeper.error { |e| $handled = e }
    Creeper.job('my.job') { |args| raise exception }
    Creeper.enqueue('my.job')
    w = Creeper::Worker.new
    w.stub(:exception_message)
    w.stub(:log)
    w.prepare
    w.work_one_job
    exception.should == $handled
  end

  it "continue working when error handler not defined" do
    Creeper.error { |e| $handled = false }
    Creeper.job('my.job') { fail }
    Creeper.enqueue('my.job')
    w = Creeper::Worker.new
    w.stub(:exception_message)
    w.stub(:log)
    w.prepare
    w.work_one_job
    false.should == $handled
  end

  it "exception raised one second before beanstalk ttr reached" do
    with_an_error_handler
    Creeper.job('my.job') { sleep(3); $handled = "didn't time out" }
    Creeper.enqueue('my.job', {}, :ttr => 2)
    w = Creeper::Worker.new
    w.stub(:exception_message)
    w.stub(:log)
    w.prepare
    w.work_one_job
    $handled.should == "didn't time out"
  end

  it "before filter gets run first" do
    Creeper.before { |name| $flag = "i_was_here" }
    Creeper.job('my.job') { |args| $handled = ($flag == 'i_was_here') }
    Creeper.enqueue('my.job')
    w = Creeper::Worker.new
    w.stub(:exception_message)
    w.stub(:log)
    w.prepare
    w.work_one_job
    true.should == $handled
  end

  it "before filter passes the name of the job" do
    Creeper.before { |name| $jobname = name }
    Creeper.job('my.job') { true }
    Creeper.enqueue('my.job')
    w = Creeper::Worker.new
    w.stub(:exception_message)
    w.stub(:log)
    w.prepare
    w.work_one_job
    'my.job'.should == $jobname
  end

  it "before filter can pass an instance var" do
    Creeper.before { |name| @foo = "hello" }
    Creeper.job('my.job') { |args| $handled = (@foo == "hello") }
    Creeper.enqueue('my.job')
    w = Creeper::Worker.new
    w.stub(:exception_message)
    w.stub(:log)
    w.prepare
    w.work_one_job
    true.should == $handled
  end

  it "before filter invokes error handler when defined" do
    with_an_error_handler
    Creeper.before { |name| fail }
    Creeper.job('my.job') {  }
    Creeper.enqueue('my.job', :foo => 123)
    w = Creeper::Worker.new
    w.stub(:exception_message)
    w.stub(:log)
    w.prepare
    w.work_one_job
    $handled.should_not == nil
    'my.job'.should ==  $job_name
    {'foo' => 123}.should == $job_args
  end

  def with_an_error_handler
    Creeper.error do |e, job_name, args|
      $handled = e.class
      $job_name = job_name
      $job_args = args
    end
  end
  
end
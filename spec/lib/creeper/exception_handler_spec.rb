require 'spec_helper'
require 'creeper'
require 'creeper/exception_handler'
require 'stringio'
require 'logger'

describe Creeper::ExceptionHandler do

  before do
    stub_const('ExceptionHandlerTestException', Class.new(StandardError))
    stub_const('TEST_EXCEPTION', ExceptionHandlerTestException.new("Something didn't work!"))
  end

  class Component
    include Creeper::Util

    def invoke_exception(args)
      raise TEST_EXCEPTION
    rescue ExceptionHandlerTestException => e
      handle_exception(e,args)
    end
  end

  describe "with mock logger" do
    before do
      @old_logger = Creeper.logger
      @str_logger = StringIO.new
      Creeper.logger = Logger.new(@str_logger)
    end

    after do
      Creeper.logger = @old_logger
    end

    it "logs the exception to Creeper.logger" do
      Component.new.invoke_exception(:a => 1)
      @str_logger.rewind
      log = @str_logger.readlines
      expect(log[0]).to match(/a=>1/)                                           # didn't include the context
      expect(log[1]).to match(/Something didn't work!/)                         # didn't include the exception message
      expect(log[2]).to match(/spec\/lib\/creeper\/exception_handler_spec\.rb/) # didn't include the backtrace
    end
  end

  describe "with fake Airbrake" do
    before do
      ::Airbrake = double('Airbrake')
    end

    after do
      Object.send(:remove_const, "Airbrake") # HACK should probably inject Airbrake etc into this class in the future
    end

    it "notifies Airbrake" do
      ::Airbrake.should_receive(:notify).with(TEST_EXCEPTION,:parameters => { :a => 1 }).and_return(nil)
      Component.new.invoke_exception(:a => 1)
    end
  end

  describe "with fake ExceptionNotifier" do
    before do
      ::ExceptionNotifier = Module.new
      ::ExceptionNotifier::Notifier = double('ExceptionNotifier::Notifier')
    end

    after do
      Object.send(:remove_const, "ExceptionNotifier")
    end

    it "notifies ExceptionNotifier" do
      ::ExceptionNotifier::Notifier.should_receive(:background_exception_notification).with(TEST_EXCEPTION, :data => { :message => { :b => 2 } }).and_return(nil)
      Component.new.invoke_exception(:b => 2)
    end
  end

  describe "with fake Exceptional" do
    before do
      ::Exceptional = Class.new do

        def self.context(msg)
          @msg = msg
        end

        def self.check_context
          @msg
        end
      end

      ::Exceptional::Config = double('Exceptional::Config')
      ::Exceptional::Remote = double('Exceptional::Remote')
      ::Exceptional::ExceptionData = double('Exceptional::ExceptionData')
    end

    after do
      Object.send(:remove_const, "Exceptional")
    end

    it "notifies Exceptional" do
      ::Exceptional::Config.should_receive(:should_send_to_api?).and_return(true)
      exception_data = double('exception_data')
      ::Exceptional::Remote.should_receive(:error).with(exception_data).and_return(nil)
      ::Exceptional::ExceptionData.should_receive(:new).with(TEST_EXCEPTION).and_return(exception_data)
      Component.new.invoke_exception(:c => 3)
      expect(::Exceptional.check_context).to eq({:c => 3}) # did not record arguments properly
    end
  end

end

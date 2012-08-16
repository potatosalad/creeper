require 'spec_helper'
require 'creeper'
require 'creeper/worker'
require 'active_record'
require 'action_mailer'
require 'creeper/rails'
require 'creeper/extensions/action_mailer'
require 'creeper/extensions/active_record'

Creeper.hook_rails!

describe Creeper::Worker do

  context 'creeper testing' do
    class PerformError < RuntimeError; end

    class DirectWorker
      include Creeper::Worker
      def perform(a, b)
        a + b
      end
    end

    class EnqueuedWorker
      include Creeper::Worker
      def perform(a, b)
        a + b
      end
    end

    class StoredWorker
      include Creeper::Worker
      def perform(error)
        raise PerformError if error
      end
    end

    class FooMailer < ActionMailer::Base
      def bar(str)
        str
      end
    end

    class FooModel < ActiveRecord::Base
      def bar(str)
        str
      end
    end

    before do
      load 'creeper/testing.rb'
    end

    after do
      # Undo override
      Creeper::Worker::ClassMethods.class_eval do
        remove_method :client_push
        alias_method :client_push, :client_push_old
        remove_method :client_push_old
      end
    end

    it 'stubs the async call' do
      expect(DirectWorker.jobs.size).to eq(0)
      expect(DirectWorker.perform_async(1, 2)).to be_true
      expect(DirectWorker.jobs.size).to eq(1)
      expect(DirectWorker.perform_in(10, 1, 2)).to be_true
      expect(DirectWorker.jobs.size).to eq(2)
      expect(DirectWorker.perform_at(10, 1, 2)).to be_true
      expect(DirectWorker.jobs.size).to eq(3)
      expect(DirectWorker.jobs.last['at']).to be_within(0.1).of(10.seconds.from_now.to_f)
    end

    it 'stubs the delay call on mailers' do
      expect(Creeper::Extensions::DelayedMailer.jobs.size).to eq(0)
      FooMailer.delay.bar('hello!')
      expect(Creeper::Extensions::DelayedMailer.jobs.size).to eq(1)
    end

    it 'stubs the delay call on models' do
      expect(Creeper::Extensions::DelayedModel.jobs.size).to eq(0)
      FooModel.delay.bar('hello!')
      expect(Creeper::Extensions::DelayedModel.jobs.size).to eq(1)
    end

    it 'stubs the enqueue call' do
      expect(EnqueuedWorker.jobs.size).to eq(0)
      expect(Creeper::Client.enqueue(EnqueuedWorker, 1, 2)).to be_true
      expect(EnqueuedWorker.jobs.size).to eq(1)
    end

    it 'executes all stored jobs' do
      expect(StoredWorker.perform_async(false)).to be_true
      expect(StoredWorker.perform_async(true)).to be_true

      expect(StoredWorker.jobs.size).to eq(2)
      expect do
        StoredWorker.drain
      end.to raise_error(PerformError)
      expect(StoredWorker.jobs.size).to eq(0)
    end

  end

end

require 'spec_helper'

describe Creeper::Worker do

  context 'a worker' do

    subject { Creeper::Worker.new }

    after(:each) do
      subject.clear!
      Creeper.clear!
    end

    it 'should have a session different from the Creeper.default_session' do
      subject.session.should_not == Creeper.default_session
      subject.session.beanstalk.should_not == Creeper.default_session.beanstalk
    end

  end
  
end
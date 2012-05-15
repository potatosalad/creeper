require 'spec_helper'

describe Creeper::Session do

  it "parses BEANSTALK_URL" do
    ENV['BEANSTALK_URL'] = "beanstalk://localhost:12300"
    Creeper::Session.new.beanstalk_addresses.should == ["localhost:12300"]
    ENV['BEANSTALK_URL'] = "beanstalk://localhost:12300/, beanstalk://localhost:12301/"
    Creeper::Session.new.beanstalk_addresses.should == ["localhost:12300","localhost:12301"]
    ENV['BEANSTALK_URL'] = "beanstalk://localhost:12300   beanstalk://localhost:12301"
    Creeper::Session.new.beanstalk_addresses.should == ["localhost:12300","localhost:12301"]
    ENV['BEANSTALK_URL'] = nil
  end
  
end
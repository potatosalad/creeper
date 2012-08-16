class UserMailer < ActionMailer::Base
  default from: "creeper@example.com"

  def greetings(now)
    @now = now
    @hostname = `hostname`.strip
    mail(:to => 'user@example.com', :subject => 'Ahoy Matey!')
  end
end

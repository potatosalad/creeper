class Post < ActiveRecord::Base

  attr_accessible :title, :body

  def long_method(other_post)
    puts "Running long method with #{self.id} and #{other_post.id}"
  end
end

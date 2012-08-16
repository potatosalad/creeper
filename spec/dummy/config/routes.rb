require 'creeper/web'

Dummy::Application.routes.draw do
  mount Creeper::Web => '/creeper'
  get "work" => "work#index"
  get "work/email" => "work#email"
  get "work/post" => "work#delayed_post"
  get "work/long" => "work#long"
  get "work/crash" => "work#crash"
  get "work/suicide" => "work#suicide"
  get "work/fast" => "work#fast"
  get "work/slow" => "work#slow"
end

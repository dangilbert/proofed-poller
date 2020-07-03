require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'
  gem 'json', require: false
  gem 'nap', require: 'rest'

end

puts 'Gems installed and loaded!'
puts "The nap gem is at version #{REST::VERSION}"

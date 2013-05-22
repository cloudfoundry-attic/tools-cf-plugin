source "http://rubygems.org"

gem "cf", :github => "cloudfoundry/cf", :tag => "v1.0.0"

gemspec

group :development, :test do
  gem "rake"
end

group :test do
  gem "rspec", "~> 2.11"
  gem "webmock", "~> 1.9"
  gem "rr", "~> 1.0"
  gem "fakefs"
  gem "blue-shell"
  gem "timecop"
end

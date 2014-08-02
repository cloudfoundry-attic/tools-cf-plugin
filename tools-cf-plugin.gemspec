# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "tools-cf-plugin/version"

Gem::Specification.new do |s|
  s.name        = "tools-cf-plugin"
  s.version     = CFTools::VERSION.dup
  s.authors     = ["Cloud Foundry"]
  s.email       = ["vcap-dev@cloudfoundry.org"]
  s.homepage    = "http://github.com/cloudfoundry/tools-cf-plugin"
  s.summary     = %q{
    Cloud Foundry tooling commands.
  }

  s.rubyforge_project = "tools-cf-plugin"

  s.add_runtime_dependency "cfoundry"
  s.add_runtime_dependency "nats"
  s.add_runtime_dependency "net-ssh"
  s.add_runtime_dependency "pry"

  s.add_development_dependency "rake", ">= 0.9"
  s.add_development_dependency "rspec", "~> 2.14"
  s.add_development_dependency "webmock", "~> 1.9"
  s.add_development_dependency "gem-release"
  s.add_development_dependency "timecop", "~> 0.6.1"
  s.add_development_dependency "shoulda-matchers", "~> 1.5.6"
  s.add_development_dependency "json_pure", "~> 1.7"
  s.add_development_dependency "blue-shell", "~> 0.3"
  s.add_development_dependency "fakefs"
  s.add_development_dependency "factory_girl"

  s.files         = %w{Rakefile} + Dir.glob("lib/**/*")
  s.test_files    = Dir.glob("spec/**/*")
  s.require_paths = ["lib"]
end

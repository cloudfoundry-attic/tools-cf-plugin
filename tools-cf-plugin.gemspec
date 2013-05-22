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

  s.add_runtime_dependency "cfoundry", ">= 1.0.0", "< 1.1"
  s.add_runtime_dependency "nats"

  s.files         = %w{Rakefile} + Dir.glob("lib/**/*")
  s.test_files    = Dir.glob("spec/**/*")
  s.require_paths = ["lib"]
end

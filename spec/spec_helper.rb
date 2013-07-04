SPEC_ROOT = File.dirname(__FILE__).freeze

require "rspec"
require "timecop"
require "cf"
require "cfoundry"
require "cfoundry/test_support"
require "webmock/rspec"
require "cf/test_support"
require "blue-shell"
require "nats/client"

require "#{SPEC_ROOT}/../lib/tools-cf-plugin/plugin"

def fixture(path)
  "#{SPEC_ROOT}/fixtures/#{path}"
end

RSpec.configure do |c|
  c.include Fake::FakeMethods

  c.include FakeHomeDir
  c.include CliHelper
  c.include InteractHelper
  c.include BlueShell::Matchers
end

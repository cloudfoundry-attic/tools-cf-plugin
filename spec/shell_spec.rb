require "spec_helper"

describe CFTools::Shell do
  let(:client) { fake_client }

  before { stub_client }

  it "starts a pry session with :quiet" do
    binding = stub

    mock.instance_of(described_class).binding { binding }
    mock(binding).pry :quiet => true

    cf %w[shell]
  end
end

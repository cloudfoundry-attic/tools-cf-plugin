require "spec_helper"

describe CFTools::Shell do
  let(:client) { fake_client }

  before { stub_client }

  it "starts a pry session with :quiet" do
    binding = double

    expect_any_instance_of(described_class).to receive(:binding).and_return(binding)
    expect(binding).to receive(:pry).with(:quiet => true)

    cf %w[shell]
  end
end

require "spec_helper"

module CFTools::Tunnel
  describe TunnelNATS do
    let(:director) { double :director, :director_uri => "http://example.com" }

    let(:deployments) do
      [{ "name" => "some-deployment",  "releases" => [{ "name" => "cf-release" }] }]
    end

    let(:deployment) { <<MANIFEST }
---
properties:
  nats:
    address: 1.2.3.4
    port: 5678
    user: natsuser
    password: natspass
  uaa:
    scim:
      users:
      - someadmin|somepass|cloud_controller.admin
  cc:
    srv_api_uri: https://api.cf.museum
MANIFEST

    let(:tunneled_port) { 65535 }

    let(:initial_client) { double }

    before do
      initial_client.stub(:token => CFoundry::AuthToken.new("initial token"))

      described_class.any_instance.stub(:connected_director => director)
      described_class.any_instance.stub(:client => initial_client)
      described_class.any_instance.stub(:tunnel_to => tunneled_port)

      CFoundry::V2::Client.any_instance.stub(:login => CFoundry::AuthToken.new(nil))

      director.stub(:list_deployments => deployments)
      director.stub(:get_deployment => { "manifest" => deployment })
    end

    it "connects to the given director" do
      expect_any_instance_of(described_class).to \
        receive(:connected_director).with("some-director.com", "someuser@somehost.com").
        and_return(director)

      cf %W[tunnel-nats some-director.com help --gateway someuser@somehost.com]
    end

    it "tunnels to the NATS server through the director" do
      expect_any_instance_of(described_class).to \
        receive(:tunnel_to).with("1.2.3.4", 5678, "someuser@somehost.com").
        and_return(tunneled_port)

      cf %W[tunnel-nats some-director.com help --gateway someuser@somehost.com]
    end

    it "logs in as the admin user from the deployment" do
      client = double
      client.stub(:token => CFoundry::AuthToken.new("bar"))

      expect(CFoundry::V2::Client).to receive(:new).with("https://api.cf.museum") do
        client
      end

      expect(client).to receive(:login).with("someadmin", "somepass") do
        CFoundry::AuthToken.new("foo")
      end

      cf %W[tunnel-nats some-director.com help]
    end

    it "invokes the given command with the NATS credentials" do
      cmd = described_class.new
      described_class.stub(:new => cmd)

      cmd.stub(:execute).and_call_original

      expect(cmd).to receive(:execute).with(Mothership.commands[:tunnel_nats], anything, anything)

      expect(cmd).to receive(:execute).with(
        Mothership.commands[:target],
        %w[
          some-arg --flag some-val --user natsuser
          --password natspass --port 65535
        ],
        anything)

      cf %W[tunnel-nats some-director.com target some-arg --flag some-val]
    end
  end
end

require "spec_helper"

module CFTools::Tunnel
  describe TunnelNATS do
    let(:director) { mock }

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

    let(:initial_client) { stub }

    before do
      stub(initial_client).token { CFoundry::AuthToken.new("initial token") }

      any_instance_of(described_class) do |cli|
        stub(cli).connected_director { director }
        stub(cli).client { initial_client }
        stub(cli).tunnel_to { tunneled_port }
      end

      any_instance_of(CFoundry::V2::Client) do |cf|
        stub(cf).login { CFoundry::AuthToken.new(nil) }
      end

      stub(director).list_deployments { deployments }
      stub(director).get_deployment { { "manifest" => deployment } }
    end

    it "connects to the given director" do
      any_instance_of(described_class) do |cli|
        mock(cli).connected_director(
            "some-director.com", "someuser@somehost.com") do
          director
        end
      end

      cf %W[tunnel-nats some-director.com help --gateway someuser@somehost.com]
    end

    it "tunnels to the NATS server through the director" do
      any_instance_of(described_class) do |cli|
        mock(cli).tunnel_to("1.2.3.4", 5678, "someuser@somehost.com") do
          tunneled_port
        end
      end

      cf %W[tunnel-nats some-director.com help --gateway someuser@somehost.com]
    end

    it "logs in as the admin user from the deployment" do
      client = mock
      stub(client).token { CFoundry::AuthToken.new("bar") }

      mock(CFoundry::V2::Client).new("https://api.cf.museum") do
        client
      end

      mock(client).login("someadmin", "somepass") do
        CFoundry::AuthToken.new("foo")
      end

      cf %W[tunnel-nats some-director.com help]
    end

    it "invokes the given command with the NATS credentials" do
      stub.proxy.instance_of(described_class).execute
      mock.instance_of(described_class).execute(
        Mothership.commands[:target],
        %w[
          some-arg --flag some-val --user natsuser
          --password natspass --port 65535
        ],
        is_a(Mothership::Inputs))

      cf %W[tunnel-nats some-director.com target some-arg --flag some-val]
    end
  end
end

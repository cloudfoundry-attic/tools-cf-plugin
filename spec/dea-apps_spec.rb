require "spec_helper"

describe CFTools::DEAApps do
  let(:client) { fake_client :apps => [app1, app2, app3] }

  let(:app1) do
    fake :app, :name => "myapp1", :guid => "myappguid-1",
      :memory => 128, :total_instances => 1
  end

  let(:app2) do
    fake :app, :name => "myapp2", :guid => "myappguid-2",
      :memory => 256, :total_instances => 2
  end

  let(:app3) do
    fake :app, :name => "myapp3", :guid => "myappguid-3",
      :memory => 1024, :total_instances => 4
  end

  before { stub_client }

  before do
    app1.stub(:exists? => true)
    app2.stub(:exists? => true)
    app3.stub(:exists? => true)
  end

  before do
    NATS.stub(:start).and_yield
    NATS.stub(:subscribe)
    EM.stub(:add_periodic_timer).and_yield
  end

  let(:heartbeat) { <<PAYLOAD }
{
  "prod": false,
  "dea": "2-4b293b726167fbc895af5a7927c0973a",
  "droplets": [
    {
      "state_timestamp": 1369251231.3436642,
      "state": "RUNNING",
      "index": 0,
      "instance": "app1-instance1",
      "version": "5c0e0e10-8384-4a35-915e-872fe91ffb95",
      "droplet": "#{app1.guid}",
      "cc_partition": "default"
    },
    {
      "state_timestamp": 1369251231.3436642,
      "state": "CRASHED",
      "index": 1,
      "instance": "app2-dead-isntance",
      "version": "deadbeef-8384-4a35-915e-872fe91ffb95",
      "droplet": "#{app2.guid}",
      "cc_partition": "default"
    },
    {
      "state_timestamp": 1369251231.3436642,
      "state": "RUNNING",
      "index": 1,
      "instance": "app2-instance1",
      "version": "deadbeef-8384-4a35-915e-872fe91ffb95",
      "droplet": "#{app2.guid}",
      "cc_partition": "default"
    },
    {
      "state_timestamp": 1369251231.3436642,
      "state": "RUNNING",
      "index": 1,
      "instance": "app2-instance2",
      "version": "deadbeef-8384-4a35-915e-872fe91ffb95",
      "droplet": "#{app2.guid}",
      "cc_partition": "default"
    },
    {
      "state_timestamp": 1369251225.2800167,
      "state": "RUNNING",
      "index": 0,
      "instance": "app3-instance1",
      "version": "bdc3b7d7-5a55-455d-ac66-ba82a9ad43e7",
      "droplet": "#{app3.guid}",
      "cc_partition": "default"
    },
    {
      "state_timestamp": 1369251225.2800167,
      "state": "RUNNING",
      "index": 0,
      "instance": "app3-instance2",
      "version": "bdc3b7d7-5a55-455d-ac66-ba82a9ad43e7",
      "droplet": "#{app3.guid}",
      "cc_partition": "default"
    },
    {
      "state_timestamp": 1369251225.2800167,
      "state": "RUNNING",
      "index": 0,
      "instance": "app3-instance3",
      "version": "bdc3b7d7-5a55-455d-ac66-ba82a9ad43e7",
      "droplet": "#{app3.guid}",
      "cc_partition": "default"
    },
    {
      "state_timestamp": 1369251225.2800167,
      "state": "RUNNING",
      "index": 0,
      "instance": "app3-instance4",
      "version": "bdc3b7d7-5a55-455d-ac66-ba82a9ad43e7",
      "droplet": "#{app3.guid}",
      "cc_partition": "default"
    }
  ]
}
PAYLOAD

  before do
    NATS.stub(:subscribe).and_yield(heartbeat)
  end

  it "outputs the list of apps, memory and math" do
    cf %W[dea-apps]
    expect(output).to say(%r{dea\s+app\s+guid\s+reserved\s+math})
    expect(output).to say(%r{2\s+myapp3\s+myappguid-3\s+4G\s+\(1G\s+x\s+4\)})
    expect(output).to say(%r{2\s+myapp2\s+myappguid-2\s+512M\s+\(256M\s+x\s+2\)})
    expect(output).to say(%r{2\s+myapp1\s+myappguid-1\s+128M\s+\(128M\s+x\s+1\)})
  end

  context "when --location is provided" do
    it "includes the org and space in the table" do
      cf %W[dea-apps --location]
      expect(output).to say(%r{^.*\s+org/space})
      expect(output).to say(%r{^.*\s+organization-\w+ / space-\w+})
      expect(output).to say(%r{^.*\s+organization-\w+ / space-\w+})
      expect(output).to say(%r{^.*\s+organization-\w+ / space-\w+})
    end
  end

  context "when --stats is provided" do
    before do
      stub_request(:get, "#{client.target}/v2/apps/#{app1.guid}/stats").
        to_return(
          :status => 200,
          :body => File.read(fixture("dea-apps/stats_1.json")))

      stub_request(:get, "#{client.target}/v2/apps/#{app2.guid}/stats").
        to_return(
          :status => 200,
          :body => File.read(fixture("dea-apps/stats_2.json")))

      stub_request(:get, "#{client.target}/v2/apps/#{app3.guid}/stats").
        to_return(
          :status => 200,
          :body => File.read(fixture("dea-apps/stats_3.json")))
    end

    it "includes the the app's running stats" do
      cf %W[dea-apps --stats]
      expect(output).to say(%r{^.*\s+stats})
      expect(output).to say(%r{^.*\s+0: 11\.2%, 1: 6\.1%, 2: 12\.5%})
      expect(output).to say(%r{^.*\s+0: 100\.0%, 1: 50\.0%})
      expect(output).to say(%r{^.*\s+0: 1\.2%})
    end

    context "when an instance is down" do
      before do
        stub_request(:get, "#{client.target}/v2/apps/#{app3.guid}/stats").
          to_return(
            :status => 200,
            :body => File.read(fixture("dea-apps/stats_3_down.json")))
      end

      it "prints the state as down for that index" do
        cf %W[dea-apps --stats]
        expect(output).to say(%r{^.*\s+stats})
        expect(output).to say(%r{^.*\s+0: 11\.2%, 1: down, 2: 12\.5%})
      end
    end
  end

  context "when the server drops the connection" do
    it "reconnects" do
      expect(NATS).to receive(:subscribe).and_raise(
        NATS::ServerError, "connection dropped")

      expect(NATS).to receive(:start).twice

      cf %W[dea-apps]
    end

    it "says it's reconnecting" do
      expect(NATS).to receive(:subscribe).and_raise(
        NATS::ServerError, "connection dropped")

      cf %W[dea-apps]

      expect(output).to say("reconnecting")
    end
  end
end

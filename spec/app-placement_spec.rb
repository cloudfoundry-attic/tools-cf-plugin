require "spec_helper"

describe CFTools::AppPlacement do
  let(:client) { fake_client :apps => [app1, app2, app3] }

  let(:app1) do
    fake :app, :name => "myapp1", :guid => "myappguid-1",
      :memory => 128, :total_instances => 2
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
    NATS.stub(:start).and_yield
    EM.stub(:add_timer).and_yield
  end

  let(:dea1_heartbeat) { <<PAYLOAD }
{
  "prod": false,
  "dea": "1-3b293b726167fbc895af5a7927c0973a",
  "droplets": [
    {
      "state_timestamp": 1369251231.3436642,
      "state": "RUNNING",
      "index": 0,
      "instance": "app1-instance2",
      "version": "5c0e0e10-8384-4a35-915e-872fe91ffb95",
      "droplet": "#{app1.guid}",
      "cc_partition": "default"
    }
  ]
}
PAYLOAD

  let(:dea2_heartbeat) { <<PAYLOAD }
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
    NATS.stub(:subscribe) do |&callback|
      callback.call(dea2_heartbeat)
      callback.call(dea1_heartbeat)
    end
  end

  it "outputs the list of guids and placements, with a zero placement assumption" do
    cf %W[app-placement]
    expect(output).to say(%r{guid\s+placement})
    expect(output).to say(%r{myappguid-1\s+0:\?\s+1:1\s+2:1\D})
    expect(output).to say(%r{myappguid-2\s+0:\?\s+1:0\s+2:2\D})
    expect(output).to say(%r{myappguid-3\s+0:\?\s+1:0\s+2:4\D})
    expect(output).to say(%r{total      \s+0:\?\s+1:1\s+2:7\D})
  end
end

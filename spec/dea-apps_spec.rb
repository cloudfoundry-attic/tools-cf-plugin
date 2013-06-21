require "spec_helper"

describe CFTools::DEAApps do
  let(:app1) { fake :app, :name => "myapp1", :guid => "myappguid-1", :memory => 128, :total_instances => 4 }
  let(:app2) { fake :app, :name => "myapp2", :guid => "myappguid-2", :memory => 256, :total_instances => 4 }
  let(:app3) { fake :app, :name => "myapp3", :guid => "myappguid-3", :memory => 1024, :total_instances => 4 }
  let(:client) { fake_client :apps => [app1, app2, app3] }

  before { stub_client }

  before {
    app1.stub(:exists? => true)
    app2.stub(:exists? => true)
    app3.stub(:exists? => true)
  }

  before do
    NATS.stub(:start).and_yield
    NATS.stub(:subscribe)
    EM.stub(:add_periodic_timer).and_yield
  end

  context "When a NATS message is recieved" do
    let(:advertise) { <<PAYLOAD }
{
  "app_id_to_count": {
    "#{app1.guid}": #{app1.total_instances},
    "#{app2.guid}": #{app2.total_instances},
    "#{app3.guid}": #{app3.total_instances}
  },
  "available_memory": 1256,
  "stacks": [
    "lucid64",
    "lucid86"
  ],
  "prod": false,
  "id": "2-1d0cf3bcd994d9f2c5ea22b9b624d77b"
}
PAYLOAD

    before do
      NATS.stub(:subscribe).and_yield(advertise)
    end

    it "outputs the list of apps, memory and math" do
      cf %W[dea-apps]
      expect(output).to say(%r{app_name\s+app_guid\s+org/space\s+reserved\s+math})
      expect(output).to say(%r{myapp3\s+myappguid-3\s+organization-\w+ / space-\w+\s+4G\s+\(1G\s+x\s+4\)})
      expect(output).to say(%r{myapp2\s+myappguid-2\s+organization-\w+ / space-\w+\s+1G\s+\(256M\s+x\s+4\)})
      expect(output).to say(%r{myapp1\s+myappguid-1\s+organization-\w+ / space-\w+\s+512M\s+\(128M\s+x\s+4\)})
    end
  end

end

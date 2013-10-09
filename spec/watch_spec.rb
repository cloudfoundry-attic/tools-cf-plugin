require "spec_helper"

describe CFTools::Watch do
  let!(:app) { fake :app, :name => "myapp", :guid => "myappguid" }

  let(:client) { fake_client :apps => [app] }

  let(:payload) { "" }
  let(:subject) { "" }
  let(:messages) { [[payload, nil, subject]] }

  before { stub_client }

  before { app.stub(:exists? => true) }

  before do
    NATS.stub(:start).and_yield
    NATS.stub(:subscribe).with(">") do |&blk|
      messages.each do |msg|
        blk.call(*msg)
      end
    end
  end

  it "subscribes all messages on NATS" do
    expect(NATS).to receive(:subscribe).with(">")
    cf %W[watch]
  end

  it "turns off output buffering" do
    # this is dumb. i know. exercise for the reader. - AS
    expect_any_instance_of(StringIO).to receive(:sync=).with(true)
    cf %W[watch]
  end

  context "when a subject is given" do
    it "subscribes to the given subject on NATS" do
      expect(NATS).to receive(:subscribe).with("some.subject")
      cf %W[watch --subject some.subject]
    end

    context "when multiple subjects are given" do
      it "subscribes to all of them on NATS" do
        expect(NATS).to receive(:subscribe).with("some.subject")
        expect(NATS).to receive(:subscribe).with("some.other.subject")
        cf %W[watch --subjects some.subject,some.other.subject]
      end
    end
  end

  context "when no application is given" do
    around { |example| Timecop.freeze(&example) }

    let(:messages) { [['{"some-message":"bar"}', nil, "some.subject"]] }

    it "prints a timestamp, message, and raw body" do
      cf %W[watch]

      expect(output).to say(/#{Time.now.strftime("%r")}\s*some.subject\s*{"some-message"=>"bar"}/)
    end
  end

  context "when no NATS server info is specified" do
    it "connects on nats:nats@127.0.0.1:4222" do
      expect(NATS).to receive(:start).with(hash_including(
        :uri => "nats://nats:nats@127.0.0.1:4222"))

      cf %W[watch]
    end
  end

  context "when NATS server info is specified" do
    it "connects to the given location using the given credentials" do
      expect(NATS).to receive(:start).with(hash_including(
        :uri => "nats://someuser:somepass@example.com:4242"))

      cf %W[watch -h example.com -P 4242 -u someuser -p somepass]
    end
  end


  context "when the server drops us for being a slow consumer" do
    it "reconnects" do
      expect(NATS).to receive(:subscribe).and_raise(
        NATS::ServerError, "Slow consumer detected, connection dropped")

      expect(NATS).to receive(:start).twice

      cf %W[watch]
    end

    it "says it's reconnecting" do
      expect(NATS).to receive(:subscribe).and_raise(
        NATS::ServerError, "Slow consumer detected, connection dropped")

      cf %W[watch]

      expect(output).to say("reconnecting")
    end
  end

  context "when NATS message logs are given" do
    let(:app) { fake :app, :guid => "some-app-guid" }
    let(:client) { fake_client :apps => [app] }

    it "does not connect to NATS" do
      expect(NATS).to_not receive(:start)
      cf %W[watch -l #{fixture("nats_logs")}/1]
    end

    it "prints the date/time from the source file, in local time" do
      cf %W[watch -l #{fixture("nats_logs")}/1]
      gmt = Time.parse("2013-07-04_18:00:36.99086 GMT")
      local = gmt.strftime("%Y-%m-%d %r")
      expect(output).to say(/^#{local}/)
    end

    context "and a subject is given" do
      it "only prints matching entries" do
        cf %W[watch -s dea.stop -l #{fixture("nats_logs")}/1]
        expect(output).to_not say("health.stop")
        expect(output).to say("dea.stop")
      end

      context "and it uses *" do
        it "only prints matching entries" do
          cf %W[watch -s *.stop -l #{fixture("nats_logs")}/1]
          expect(output).to say("health.stop")
          expect(output).to say("dea.stop")
          expect(output).to_not say("foo.bar")
        end

        it "matches based on segment length" do
          cf %W[watch -s * -l #{fixture("nats_logs")}/1]
          expect(output).to_not say("health.stop")
          expect(output).to_not say("dea.stop")
          expect(output).to_not say("foo.bar")
          expect(output).to say("foo")
        end
      end

      context "and it uses >" do
        it "only prints matching entries" do
          cf %W[watch -s foo.> -l #{fixture("nats_logs")}/1]
          expect(output).to_not say("health.stop")
          expect(output).to_not say("dea.stop")
          expect(output).to say("foo.bar")
        end
      end
    end
  end

  context "when a malformed message comes in" do
    let(:messages) { [["foo", nil, "some.subject"]] }

    it "prints an error message and keeps on truckin'" do
      described_class.any_instance.stub(:process_message).and_raise("hell")

      cf %W[watch]

      expect(output).to say(
        "couldn't deal w/ some.subject 'foo': RuntimeError: hell")
    end
  end

  context "when a message comes in with a reply channel, followed by a reply" do
    let(:messages) do
      [
        ['{"foo":"bar"}', "some-reply", "some.subject"],
        ['{"some-response":"other"}', nil, "some-reply"]
      ]
    end

    it "registers it in #requests" do
      cf %W[watch]

      expect(output).to say(/some\.subject             \(1\)\s*{"foo"=>"bar"}/)
      expect(output).to say(/`- reply to some\.subject \(1\)\s+{"some-response"=>"other"}/)
    end
  end

  context "when an application is given" do
    context "and it cannot be found" do
      it "prints a failure message" do
        cf %W[watch some-bogus-app]
        expect(error_output).to say("Unknown app 'some-bogus-app'")
      end

      it "exits with a non-zero status" do
        expect(cf %W[watch some-bogus-app]).to_not eq(0)
      end
    end

    context "and multiple apps with the sane name are found" do
      let!(:org1) { fake :organization, :name => "org1" }
      let!(:org2) { fake :organization, :name => "org2" }
      let!(:space1) { fake :space, :name => "space1", :organization => org1 }
      let!(:space2) { fake :space, :name => "space2", :organization => org2 }
      let!(:app1) { fake :app, :name => "myapp", :guid => "myappguid", :space => space1 }
      let!(:app2) { fake :app, :name => "myapp", :guid => "myappguid", :space => space2 }

      let(:client) { fake_client :apps => [app1, app2] }

      it "asks to disambiguate" do
        should_ask("Which application?", hash_including(:choices => [app1, app2])) do |_, opts|
          expect(opts[:display].call(app1)).to eq("myapp (org1/space1)")
        end

        cf %W[watch myapp]
      end
    end

    context "and a message containing the app's GUID is seen" do
      around { |example| Timecop.freeze(&example) }

      let(:messages) { [["{\"foo\":\"some-message-mentioning-#{app.guid}\"}", nil, "some.subject"]] }

      it "prints a timestamp, message, and raw body" do
        cf %W[watch myapp]

        expect(output).to say(/#{Time.now.strftime("%r")}\s*some.subject\s*{"foo"=>"some-message-mentioning-#{app.guid}"}/)
      end
    end

    context "when a message NOT containing the app's GUID is seen" do
      let(:messages) { [["some-irrelevant-message", nil, "some.subject"]] }

      it "does not print it" do
        cf %W[watch myapp]

        expect(output).to_not say("some.subject")
      end
    end
  end

  context "when a message is seen with subject droplet.exited" do
    let(:subject) { "droplet.exited" }

    let(:payload) { <<PAYLOAD }
{
  "exit_description": "",
  "exit_status": -1,
  "reason": "STOPPED",
  "index": 0,
  "instance": "2e2b8ca31e87dd3a26cee0ddba01e84e",
  "version": "aaca113b-3ff9-4c04-8e69-28f8dc9d8cc0",
  "droplet": "#{app.guid}",
  "cc_partition": "default"
}
PAYLOAD

    it "pretty-prints the message body" do
      cf %W[watch]

      expect(output).to say("app: myapp, reason: STOPPED, index: 0, version: aaca113b")
    end
  end

  context "when a message is seen with subject dea.heartbeat" do
    let(:subject) { "dea.heartbeat" }

    let(:payload) { <<PAYLOAD }
{
  "prod": false,
  "dea": "1-4b293b726167fbc895af5a7927c0973a",
  "droplets": [
    {
      "state_timestamp": 1369251231.3436642,
      "state": "RUNNING",
      "index": 0,
      "instance": "some app instance",
      "version": "beefdead-8384-4a35-915e-872fe91ffb95",
      "droplet": "#{app.guid}",
      "cc_partition": "default"
    },
    {
      "state_timestamp": 1369251231.3436642,
      "state": "CRASHED",
      "index": 1,
      "instance": "some other app instance",
      "version": "deadbeef-8384-4a35-915e-872fe91ffb95",
      "droplet": "#{app.guid}",
      "cc_partition": "default"
    },
    {
      "state_timestamp": 1369251225.2800167,
      "state": "RUNNING",
      "index": 0,
      "instance": "some other other app instance",
      "version": "bdc3b7d7-5a55-455d-ac66-ba82a9ad43e7",
      "droplet": "eaebd610-0e15-4935-9784-b676d7d8495e",
      "cc_partition": "default"
    }
  ]
}
PAYLOAD

    context "and an application is given" do
      it "prints only the application's entry" do
        cf %W[watch myapp]

        expect(output).to say("dea: 1, running: 1 (myapp @ beefdead), crashed: 1 (myapp @ deadbeef)")
      end
    end
  end

  context "when a message is seen with subject dea.advertise" do
    let(:subject) { "dea.advertise" }

    let(:other_app) { fake :app, :name => "otherapp", :guid => "otherguid" }

    let(:client) { fake_client :apps => [app, other_app] }

    let(:payload) { <<PAYLOAD }
{
  "app_id_to_count": {
    "#{app.guid}": 1,
    "#{other_app.guid}": 2
  },
  "available_memory": 30000,
  "stacks": [
    "lucid64"
  ],
  "prod": false,
  "id": "1-f158dcd026d1589853846a3859faf0ea"
}
PAYLOAD

    context "and app is given" do
      it "prints nothing" do
        cf %W[watch myapp]

        expect(output).to_not say("dea.advertise")
      end
    end

    context "and app is NOT given" do
      before do
        app.stub(:exists? => true)
        other_app.stub(:exists? => false)
      end

      it "prints the dea, its stacks, available memory, and apps" do
        cf %W[watch]

        expect(output).to say("dea: 1, stacks: lucid64, available mem: 29G, apps: 1 x myapp, 2 x unknown")
      end

      context "and it does not include app counts" do
        let(:payload) { <<PAYLOAD }
{
  "available_memory": 30000,
  "stacks": [
    "lucid64"
  ],
  "prod": false,
  "id": "1-f158dcd026d1589853846a3859faf0ea"
}
PAYLOAD

        it "prints 'none' for the app listing" do
          cf %W[watch]

          expect(output).to say("dea: 1, stacks: lucid64, available mem: 29G, apps: none")
        end
      end
    end
  end

  context "when a message is seen with subject staging.advertise" do
    let(:subject) { "staging.advertise" }

    let(:payload) { <<PAYLOAD }
{
  "available_memory": 27264,
  "stacks": [
    "lucid64"
  ],
  "id": "1-7b56cfd786123e56423cf700103f54a8"
}
PAYLOAD

    it "prints the dea, its stacks, and its available memory" do
      cf %W[watch]

      expect(output).to say("dea: 1, stacks: lucid64, available mem: 27G")
    end
  end

  context "when a message is seen with subject router.start" do
    let(:subject) { "router.start" }

    let(:payload) { <<PAYLOAD }
{
"hosts": [
  "10.10.16.15"
],
"id": "11bb18232f3afdc5cad2b583f8d000f5"
}
PAYLOAD

    it "prints the hosts" do
      cf %W[watch]

      expect(output).to say("hosts: 10.10.16.15")
    end
  end

  context "when a message is seen with subject router.register" do
    let(:subject) { "router.register" }

    context "when the app flag is passed in" do
      context "when there's an associated DEA" do
        let(:payload) { <<PAYLOAD }
{
  "private_instance_id": "e4a5ee2330c81fd7611eba7dbedbb499a00ae1b79f97f40a3603c8bff6fbcc6f",
  "tags": {},
  "port": 61111,
  "host": "192.0.43.10",
  "uris": [
    "my-app.com",
    "my-app-2.com"
  ],
  "app": "#{app.guid}",
  "dea": "1-4b293b726167fbc895af5a7927c0973a"
}
PAYLOAD

        it "prints the uris, host, and port" do
          cf %W[watch --app #{app.name}]

          expect(output).to say("app: myapp, dea: 1, uris: my-app.com, my-app-2.com, host: 192.0.43.10, port: 61111")
        end
      end
    end

    context "when the app flag is not passed in" do
      let(:payload) { <<PAYLOAD }
{
  "private_instance_id": "e4a5ee2330c81fd7611eba7dbedbb499a00ae1b79f97f40a3603c8bff6fbcc6f",
  "tags": {},
  "port": 61111,
  "host": "192.0.43.10",
  "uris": [
    "my-app.com",
    "my-app-2.com"
  ],
  "app": "some_unkown_guid",
  "dea": "1-4b293b726167fbc895af5a7927c0973a"
}
PAYLOAD

      it "does not print anything" do
        cf %W[watch]

        expect(output).to_not say("uris: my-app.com, my-app-2.com, host: 192.0.43.10, port: 61111")
      end
    end

    context "when there's NOT an associated DEA" do
      let(:payload) { <<PAYLOAD }
{
  "private_instance_id": "e4a5ee2330c81fd7611eba7dbedbb499a00ae1b79f97f40a3603c8bff6fbcc6f",
  "tags": {},
  "port": 61111,
  "host": "192.0.43.10",
  "uris": [
    "my-app.com",
    "my-app-2.com"
  ]
}
PAYLOAD
      it "prints the uris, host, and port" do
        cf %W[watch]

        expect(output).to say("uris: my-app.com, my-app-2.com, host: 192.0.43.10, port: 61111")
      end
    end
  end

  context "when a message is seen with subject router.unregister" do
    let(:subject) { "router.unregister" }

    context "when there's an associated DEA" do
      let(:payload) { <<PAYLOAD }
{
  "private_instance_id": "9ade4a089b26c3aa179edec08db65f47c8379ba2c4f4da625d5180ca97c3ef04",
  "tags": {},
  "port": 61111,
  "host": "192.0.43.10",
  "uris": [
    "my-app.com"
  ],
  "app": "#{app.guid}",
  "dea": "5-029eb34eef489818abbc08413e4a70d9"
}
PAYLOAD

      it "prints the dea, uris, host, and port" do
        cf %W[watch]

        expect(output).to say("app: myapp, dea: 5, uris: my-app.com, host: 192.0.43.10, port: 61111")
      end
    end

    context "when no app is specified and there's NOT an associated DEA" do
      let(:payload) { <<PAYLOAD }
{
  "private_instance_id": "9ade4a089b26c3aa179edec08db65f47c8379ba2c4f4da625d5180ca97c3ef04",
  "tags": {},
  "port": 61111,
  "host": "192.0.43.10",
  "uris": [
    "my-app.com"
  ]
}
PAYLOAD

      it "prints the uris, host, and port" do
        cf %W[watch]

        expect(output).to say("uris: my-app.com, host: 192.0.43.10, port: 61111")
      end
    end
  end

  context "when a message is seen with subject dea.*.start" do
    let(:subject) { "dea.42-deadbeef.start" }

    let(:payload) { <<PAYLOAD }
{
  "index": 2,
  "debug": null,
  "console": true,
  "env": [],
  "cc_partition": "default",
  "limits": {
    "fds": 16384,
    "disk": 1024,
    "mem": 128
  },
  "services": [],
  "droplet": "#{app.guid}",
  "name": "hello-sinatra",
  "uris": [
    "myapp.com"
  ],
  "prod": false,
  "sha1": "9c8f36ee81b535a7d9b4efcd9d629e8cf8a2645f",
  "executableFile": "deprecated",
  "executableUri": "https://a1-cf-app-com-cc-droplets.s3.amazonaws.com/ac/cf/accf1078-e7e1-439a-bd32-77296390c406?AWSAccessKeyId=AKIAIMGCF7E5F6M5RV3A&Signature=1lyIotK3cZ2VUyK3H8YrlT82B8c%3D&Expires=1369259081",
  "version": "ce1da6af-59b1-4fea-9e39-64c19440a671"
}
PAYLOAD

    it "filters the uuid from the subject" do
      cf %W[watch]

      expect(output).to say("dea.42.start")
    end

    it "prints the app, dea, index, version, and uris" do
      cf %W[watch]

      expect(output).to say("app: myapp, dea: 42, index: 2, version: ce1da6af, uris: myapp.com")
    end

    context "when a single uri is given as a string" do
      let(:payload) { <<PAYLOAD }
{
  "index": 2,
  "debug": null,
  "console": true,
  "env": [],
  "cc_partition": "default",
  "limits": {
    "fds": 16384,
    "disk": 1024,
    "mem": 128
  },
  "services": [],
  "droplet": "#{app.guid}",
  "name": "hello-sinatra",
  "uris": "myapp.com",
  "prod": false,
  "sha1": "9c8f36ee81b535a7d9b4efcd9d629e8cf8a2645f",
  "executableFile": "deprecated",
  "executableUri": "https://a1-cf-app-com-cc-droplets.s3.amazonaws.com/ac/cf/accf1078-e7e1-439a-bd32-77296390c406?AWSAccessKeyId=AKIAIMGCF7E5F6M5RV3A&Signature=1lyIotK3cZ2VUyK3H8YrlT82B8c%3D&Expires=1369259081",
  "version": "ce1da6af-59b1-4fea-9e39-64c19440a671"
}
PAYLOAD

      it "prints the app, dea, index, version, and uris" do
        cf %W[watch]

        expect(output).to say("app: myapp, dea: 42, index: 2, version: ce1da6af, uris: myapp.com")
      end
    end
  end

  context "when a message is seen with subject droplet.updated" do
    let(:subject) { "droplet.updated" }

    let(:payload) { <<PAYLOAD }
{
  "cc_partition": "default",
  "droplet": "#{app.guid}"
}

PAYLOAD

    it "prints the app that was updated" do
      cf %W[watch]

      expect(output).to say("app: myapp")
      expect(output).to_not say("cc_partition")
    end
  end

  context "when a message is seen with subject dea.stop" do
    let(:subject) { "dea.stop" }

    context "and it's stopping particular indices" do
      let(:payload) { <<PAYLOAD }
{
  "indices": [
    1,
    2
  ],
  "version": "ce1da6af-59b1-4fea-9e39-64c19440a671",
  "droplet": "#{app.guid}"
}
PAYLOAD

      it "prints that it's scaling down, and the affected indices" do
        cf %W[watch]

        expect(output).to say("app: myapp, version: ce1da6af, scaling down indices: 1, 2")
      end
    end

    context "when it's specifying instances (i.e. from HM)" do
      let(:payload) { <<PAYLOAD }
{
  "instances": [
    "a",
    "b",
    "c"
  ],
  "droplet": "#{app.guid}"
}
PAYLOAD
      it "prints that it's killing extra instances" do
        cf %W[watch]

        expect(output).to say("app: myapp, killing extra instances: a, b, c")
      end
    end

    context "when it's stopping the entire application" do
      let(:payload) { <<PAYLOAD }
{
  "droplet": "#{app.guid}"
}
PAYLOAD

      it "prints that it's killing extra instances" do
        cf %W[watch]

        expect(output).to say("app: myapp, stopping application")
      end
    end
  end

  context "when a message is seen with subject dea.update" do
    let(:subject) { "dea.update" }

    let(:payload) { <<PAYLOAD }
{
  "uris": [
    "myapp.com",
    "myotherroute.com"
  ],
  "droplet": "#{app.guid}",
  "version": "deadbeef-bar-baz",
}
PAYLOAD

    it "prints the new uris and new version" do
      cf %W[watch]

      expect(output).to say("app: myapp, uris: myapp.com, myotherroute.com, new version: deadbeef")
    end
  end

  context "when a message is seen with subject dea.find.droplet" do
    let(:subject) { "dea.find.droplet" }

    let(:payload) { <<PAYLOAD }
{
  "version": "878318bf-64a0-4055-b79b-46871292ceb8",
  "states": [
    "STARTING",
    "RUNNING"
  ],
  "droplet": "#{app.guid}"
}
PAYLOAD

    let(:state_timestamp) { "1369262704.3337305" }

    let(:response_payload) { <<PAYLOAD }
{
  "console_port": 61016,
  "console_ip": "10.10.17.1",
  "staged": "/7cc4f4fe64c7a0fbfaacf71e9e222a35",
  "credentials": [
    "8a3890704d0d08e7bc291a0d11801c4e",
    "ba7e9e6d09170c4d3e794033fa76be97"
  ],
  "dea": "1-c0d2928b36c524153cdc8cfb51d80f75",
  "droplet": "#{app.guid}",
  "version": "878318bf-0cf4-403d-a54d-1c0970dca50d",
  "instance": "7cc4f4fe64c7a0fbfaacf71e9e222a35",
  "index": 0,
  "state": "RUNNING",
  "state_timestamp": #{state_timestamp},
  "file_uri": "http://10.10.17.1:12345/instances"
}
PAYLOAD

    it "prints the states being queried" do
      cf %W[watch]

      expect(output).to say("app: myapp, version: 878318bf, querying states: starting, running")
    end

    context "when there are no states being queried" do
      let(:payload) { <<PAYLOAD }
{
  "version": "878318bf-64a0-4055-b79b-46871292ceb8",
  "droplet": "#{app.guid}"
}
PAYLOAD

      it "prints them as 'none'" do
        cf %W[watch]

        expect(output).to say("app: myapp, version: 878318bf, querying states: none")
      end
    end

    context "and we see the response" do
      let(:messages) do
        [ [payload, "some-inbox", "dea.find.droplet"],
          [response_payload, nil, "some-inbox"]
        ]
      end

      it "pretty-prints the response" do
        cf %W[watch]

        expect(output).to say("reply to dea.find.droplet (1)\tdea: 1, index: 0, state: running, version: 878318bf, since: #{Time.at(state_timestamp.to_f)}")
      end
    end
  end

  context "when a message is seen with subject healthmanager.status" do
    let(:subject) { "healthmanager.status" }

    let(:payload) { <<PAYLOAD }
{
  "version": "50512eed-674e-4991-9ada-a583633c0cd4",
  "state": "FLAPPING",
  "droplet": "#{app.guid}"
}
PAYLOAD

    let(:response_payload) { <<PAYLOAD }
{
  "indices": [
    1,
    2
  ]
}
PAYLOAD

    it "prints the states being queried" do
      cf %W[watch]

      expect(output).to say("app: myapp, version: 50512eed, querying states: flapping")
    end

    context "and we see the response" do
      let(:messages) do
        [ [payload, "some-inbox", "healthmanager.status"],
          [response_payload, nil, "some-inbox"]
        ]
      end

      it "pretty-prints the response" do
        cf %W[watch]

        expect(output).to say("reply to healthmanager.status (1)\tindices: 1, 2")
      end
    end
  end

  context "when a message is seen with subject healthmanager.health" do
    let(:subject) { "healthmanager.health" }

    let(:other_app) { fake :app, :name => "otherapp" }

    let(:client) { fake_client :apps => [app, other_app] }

    let(:payload) { <<PAYLOAD }
{
  "droplets": [
    {
      "version": "deadbeef-foo",
      "droplet": "#{app.guid}"
    },
    {
      "version": "beefdead-foo",
      "droplet": "#{other_app.guid}"
    }
  ]
}
PAYLOAD

    let(:response_payload) { <<PAYLOAD }
{
  "healthy": 2,
  "version": "deadbeef-foo",
  "droplet": "#{app.guid}"
}
PAYLOAD

    let(:other_response_payload) { <<PAYLOAD }
{
  "healthy": 3,
  "version": "beefdead-foo",
  "droplet": "#{other_app.guid}"
}
PAYLOAD

    before { other_app.stub(:exists? => true) }

    it "prints the apps whose health being queried" do
      cf %W[watch]

      expect(output).to say("querying health for: myapp (deadbeef), otherapp (beefdead)")
    end

    context "and we see the response" do
      let(:messages) do
        [ [payload, "some-inbox", "healthmanager.health"],
          [response_payload, nil, "some-inbox"],
          [other_response_payload, nil, "some-inbox"]
        ]
      end

      it "pretty-prints the response" do
        cf %W[watch]

        expect(output).to say("reply to healthmanager.health (1)\tapp: myapp, version: deadbeef, healthy: 2")
        expect(output).to say("reply to healthmanager.health (1)\tapp: otherapp, version: beefdead, healthy: 3")
      end
    end
  end

  context "when a message is seen with subject dea.shutdown" do
    let(:subject) { "dea.shutdown" }

    let(:other_app) { fake :app, :name => "otherapp" }

    let(:client) { fake_client :apps => [app, other_app] }

    let(:payload) { <<PAYLOAD }
{
  "app_id_to_count": {
    "#{app.guid}": 1,
    "#{other_app.guid}": 2
  },
  "version": "0.0.1",
  "ip": "1.2.3.4",
  "id": "0-deadbeef"
}
PAYLOAD

    context "and the apps still exist" do
      before do
        app.stub(:exists? => true)
        other_app.stub(:exists? => true)
      end

      it "prints the DEA and affected applications" do
        cf %W[watch]

        expect(output).to say("dea: 0, apps: 1 x myapp, 2 x otherapp")
      end
    end

    context "and an app no longer exists" do
      before do
        app.stub(:exists? => true)
        other_app.stub(:exists? => false)
      end

      it "prints the DEA and affected applications" do
        cf %W[watch]

        expect(output).to say(
          "dea: 0, apps: 1 x myapp, 2 x unknown (#{other_app.guid})")
      end
    end
  end

  context "when a message is seen with subject health.start" do
    let(:subject) { "health.start" }

    let(:last_updated) { Time.now }

    let(:payload) { <<PAYLOAD }
{
  "indices": [
    1,
    3
  ],
  "running": {
    "deadbeef-version": 1,
    "beefdead-version": 2
  },
  "version": "deadbeef-foo",
  "last_updated": #{last_updated.to_i},
  "droplet": "#{app.guid}"
}
PAYLOAD

    it "prints the operation, last updated timestamp, and instances" do
      cf %W[watch]

      expect(output).to say(
        "app: myapp, version: deadbeef, indices: 1, 3, running: 1 x deadbeef, 2 x beefdead")
    end
  end

  context "when a message is seen with subject health.stop" do
    let(:subject) { "health.stop" }

    let(:last_updated) { Time.now }

    let(:payload) { <<PAYLOAD }
{
  "instances": {
    "some-instance": "deadbeef-version",
    "some-other-instance": "beefdead-version"
  },
  "running": {
    "deadbeef-version": 1,
    "beefdead-version": 2
  },
  "last_updated": #{last_updated.to_i},
  "droplet": "#{app.guid}"
}
PAYLOAD

    it "prints the operation, last updated timestamp, and instances" do
      cf %W[watch]

      expect(output).to say(
        "app: myapp, instances: some-instance (deadbeef), some-other-instance (beefdead), running: 1 x deadbeef, 2 x beefdead")
    end
  end

  context "when a message is seen with subject *.announce" do
    let(:subject) { "QaaS.announce" }

    let(:payload) { <<PAYLOAD }
{
"supported_versions": [
  "n/a"
],
"plan": "1dolla",
"id": "quarters_as_a_service",
"capacity_unit": 1,
"max_capacity": 100,
"available_capacity": 100
}
PAYLOAD

    it "prints the dea, its stacks, and its available memory" do
      cf %W[watch]

      expect(output).to say("id: quarters_as_a_service, plan: 1dolla, supported versions: n/a, capacity: (available: 100, max: 100, unit: 1)")
    end
  end

  context "when a message is seen with subject vcap.component.announce" do
    let(:subject) { "vcap.component.announce" }

    let(:payload) { <<PAYLOAD }
{
"start": "2013-05-24 16:45:01 +0000",
"credentials": [
  "cb68328a26f68416eabbad702c542000",
  "0e6b5ec19df10c7ba2e7f36cdf33474e"
],
"host": "10.10.32.10:39195",
"uuid": "some-uuid",
"index": 0,
"type": "QaaS-Provisioner"
}
PAYLOAD

    it "prints the type, index, host, start time" do
      cf %W[watch]

      expect(output).to say("type: QaaS-Provisioner, index: 0, uuid: some-uuid, start time: 2013-05-24 16:45:01 +0000")
    end
  end

  context "when a message is seen with subject vcap.component.discover" do
    let(:subject) { "vcap.component.discover" }

    let(:payload) { "" }

    let(:response_payload) { <<PAYLOAD }
{
  "uptime": "0d:23h:51m:21s",
  "start": "2013-05-24 17:58:08 +0000",
  "credentials": [
    "user",
    "pass"
  ],
  "host": "1.2.3.4:8080",
  "uuid": "4-deadbeef",
  "index": 4,
  "type": "DEA"
}
PAYLOAD

    it "prints the states being queried" do
      cf %W[watch]

      expect(output).to say("vcap.component.discover")
    end

    context "and we see the response" do
      let(:messages) do
        [ [payload, "some-inbox", "vcap.component.discover"],
          [response_payload, nil, "some-inbox"]
        ]
      end

      it "pretty-prints the response" do
        cf %W[watch]

        expect(output).to say("reply to vcap.component.discover (1)\ttype: DEA, index: 4, uri: user:pass@1.2.3.4:8080, uptime: 0d:23h:51m:21s")
      end

      context "and there's no uptime" do
        let(:response_payload) { <<PAYLOAD }
{
  "start": "2013-05-24 17:58:08 +0000",
  "credentials": [
    "user",
    "pass"
  ],
  "host": "1.2.3.4:8080",
  "uuid": "1-deadbeef",
  "index": 1,
  "type": "login"
}
PAYLOAD

        it "does not include it in the message" do
          cf %W[watch]

          expect(output).to say("reply to vcap.component.discover (1)\ttype: login, index: 1, uri: user:pass@1.2.3.4:8080")
        end
      end
    end
  end
end

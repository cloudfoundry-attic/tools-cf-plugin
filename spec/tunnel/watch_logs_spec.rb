require "spec_helper"

module CFTools::Tunnel
  describe WatchLogs do
    let(:director_uri) { "https://some-director.com:25555" }

    let(:director) { Bosh::Cli::Director.new(director_uri) }

    let(:stream) { stub }

    let(:vms) do
      [ { "ips" => ["1.2.3.4"], "job_name" => "cloud_controller", "index" => 0 },
        { "ips" => ["1.2.3.5"], "job_name" => "dea_next", "index" => 0 },
        { "ips" => ["1.2.3.6"], "job_name" => "dea_next", "index" => 1 }
      ]
    end

    let(:deployments) do
      [{ "name" => "some-deployment",  "releases" => [{ "name" => "cf-release" }] }]
    end

    def mock_cli
      any_instance_of(described_class) do |cli|
        mock(cli)
      end
    end

    def stub_cli
      any_instance_of(described_class) do |cli|
        stub(cli)
      end
    end

    before do
      stub(director).list_deployments { deployments }
      stub(director).fetch_vm_state { vms }
      stub_cli.connected_director { director }

      stub(stream).stream
      stub_cli.stream_for { stream }
    end

    it "connects to the given director" do
      mock_cli.connected_director(
          "some-director.com", "someuser@somehost.com") do
        director
      end

      cf %W[watch-logs some-director.com --gateway someuser@somehost.com]
    end

    context "when no gateway user/host is specified" do
      it "defaults to vcap@director" do
        mock_cli.connected_director(
            "some-director.com", "vcap@some-director.com") do
          director
        end

        cf %W[watch-logs some-director.com]
      end
    end

    context "when there are no jobs to log" do
      let(:vms) { [] }

      it "fails with a message" do
        cf %W[watch-logs some-director.com]
        expect(error_output).to say("No locations found.")
      end
    end

    context "when there are jobs to log" do
      it "streams their locations" do
        mock(stream).stream(anything) do |locations, blk|
          expect(locations).to include("1.2.3.4")
          expect(locations).to include("1.2.3.5")
          expect(locations).to include("1.2.3.6")
        end

        cf %W[watch-logs some-director.com]
      end

      it "pretty-prints their log entries" do
        entry1_time = Time.new(2011, 06, 21, 1, 2, 3)
        entry2_time = Time.new(2011, 06, 21, 1, 2, 4)
        entry3_time = Time.new(2011, 06, 21, 1, 2, 5)

        entry1 = LogEntry.new(
          "cloud_controller/0",
          %Q[{"message":"a","timestamp":#{entry1_time.to_f},"log_level":"info"}],
          :stdout)

        entry2 = LogEntry.new(
          "dea_next/1",
          %Q[{"message":"b","timestamp":#{entry2_time.to_f},"log_level":"warn"}],
          :stdout)

        entry3 = LogEntry.new(
          "dea_next/0",
          %Q[{"message":"c","timestamp":#{entry3_time.to_f},"log_level":"error"}],
          :stdout)

        mock(stream).stream(anything) do |locations, blk|
          blk.call(entry1)
          blk.call(entry2)
          blk.call(entry3)
        end

        cf %W[watch-logs some-director.com]

        expect(output).to say("cloud_controller/0   01:02:03 AM  info    a\n")
        expect(output).to say("dea_next/1           01:02:04 AM  warn    b\n")
        expect(output).to say("dea_next/0           01:02:05 AM  error   c\n")
      end
    end
  end
end

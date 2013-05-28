require "spec_helper"

module CFTools::Tunnel
  describe MultiLineStream do
    let(:director) { stub }
    let(:deployment) { "some-deployment" }
    let(:gateway_user) { "vcap" }
    let(:gateway_host) { "vcap.me" }

    let(:gateway) { stub }
    let(:entries) { Queue.new }

    subject do
      described_class.new(director, deployment, gateway_user, gateway_host)
    end

    before do
      stub(subject).create_ssh_user { ["1.2.3.4", "some_user_1"] }
      stub(subject).gateway { gateway }
      stub(subject).entry_queue { entries }
      stub(Thread).new { |blk| blk.call }
    end

    describe "#stream" do
      it "yields entries as they come through the queue" do
        entries << :a
        entries << :b
        entries << nil

        seen = []
        subject.stream({}) do |e|
          seen << e
        end
        
        expect(seen).to eq([:a, :b])
      end

      it "spawns a SSH tunnel for each location" do
        mock(Thread).new { |blk| blk.call }.ordered
        mock(Thread).new { |blk| blk.call }.ordered

        mock(subject).create_ssh_user("foo", 0, entries) { ["1.2.3.4", "some_user_1"] }
        mock(subject).create_ssh_user("bar", 0, entries) { ["1.2.3.5", "some_user_2"] }

        mock(gateway).ssh("1.2.3.4", "some_user_1")
        mock(gateway).ssh("1.2.3.5", "some_user_2")

        entries << nil

        subject.stream(["foo", 0] => [], ["bar", 0]=> [])
      end

      it "streams from each location" do
        ssh = stub

        locations = {
          "1.2.3.4" => [
            StreamLocation.new("some/path", "some-label"),
            StreamLocation.new("some/other/path", "some-label")
          ],
          "1.2.3.5" => [
            StreamLocation.new("some/path", "other-label"),
          ]
        }

        locations.each do |_, locs|
          locs.each do |loc|
            mock(loc).stream_lines(ssh)
          end
        end

        stub(gateway).ssh { |_, _, blk| blk.call(ssh) }

        entries << nil

        subject.stream(locations)
      end
    end
  end
end

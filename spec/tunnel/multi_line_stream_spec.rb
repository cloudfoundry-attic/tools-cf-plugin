require "spec_helper"

module CFTools::Tunnel
  describe MultiLineStream do
    let(:gateway_user) { "vcap" }
    let(:gateway_host) { "vcap.me" }

    let(:gateway) { stub }
    let(:entries) { Queue.new }

    subject { described_class.new(gateway_user, gateway_host) }

    before do
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

        mock(gateway).ssh("1.2.3.4", gateway_user)
        mock(gateway).ssh("1.2.3.5", gateway_user)

        entries << nil

        subject.stream("1.2.3.4" => [], "1.2.3.5" => [])
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

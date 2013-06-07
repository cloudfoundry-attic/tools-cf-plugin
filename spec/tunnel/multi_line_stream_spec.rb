require "spec_helper"

module CFTools::Tunnel
  describe MultiLineStream do
    let(:director) { double }
    let(:deployment) { "some-deployment" }
    let(:gateway_user) { "vcap" }
    let(:gateway_host) { "vcap.me" }

    let(:gateway) { double }
    let(:entries) { Queue.new }

    subject do
      described_class.new(director, deployment, gateway_user, gateway_host)
    end

    before do
      subject.stub(:create_ssh_user => ["1.2.3.4", "some_user_1"])
      subject.stub(:gateway => gateway)
      subject.stub(:entry_queue => entries)
      Thread.stub(:new).and_yield
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
        expect(Thread).to receive(:new).ordered
        expect(Thread).to receive(:new).ordered

        expect(subject).to receive(:create_ssh_user).with("foo", 0, entries) { ["1.2.3.4", "some_user_1"] }
        expect(subject).to receive(:create_ssh_user).with("bar", 0, entries) { ["1.2.3.5", "some_user_2"] }

        expect(gateway).to receive(:ssh).with("1.2.3.4", "some_user_1")
        expect(gateway).to receive(:ssh).with("1.2.3.5", "some_user_2")

        entries << nil

        subject.stream(["foo", 0] => [], ["bar", 0]=> [])
      end

      it "streams from each location" do
        ssh = double

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
            expect(loc).to receive(:stream_lines).with(ssh)
          end
        end

        gateway.stub(:ssh).and_yield(ssh)

        entries << nil

        subject.stream(locations)
      end

      context "when streaming fails" do
        it "retries" do
          called = 0
          subject.stub(:stream_location) do
            called += 1
            raise "boom" if called == 1
          end

          entries << nil

          subject.stream("1.2.3.4" => [])

          expect(called).to eq(2)
        end
      end
    end
  end
end

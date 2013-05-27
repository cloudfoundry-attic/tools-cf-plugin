require "spec_helper"

describe CFTools::Tunnel::StreamLocation do
  let(:path) { "some/file" }
  let(:label) { "some_component/0" }

  subject { described_class.new(path, label) }

  describe "#path" do
    let(:path) { "some/path" }

    it "returns the path of the entry" do
      expect(subject.path).to eq("some/path")
    end
  end

  describe "#label" do
    let(:label) { "some-label" }

    it "returns the label of the entry" do
      expect(subject.label).to eq("some-label")
    end
  end

  describe "#stream_lines" do
    let(:ssh) { stub }

    it "tails the file under /var/vcap/sys/log" do
      mock(ssh).exec("tail -f /var/vcap/sys/log/#{path}")
      subject.stream_lines(ssh)
    end

    it "yields log entries as lines come through the channel" do
      stub(ssh).exec { |_, blk| blk.call({}, :stdout, "foo\nbar\n") }

      lines = []
      subject.stream_lines(ssh) do |entry|
        lines << entry.message
      end

      expect(lines).to eq(["foo\n", "bar\n"])
    end

    it "merges chunks that form a complete line" do
      channel = {}
      stub(ssh).exec do |_, blk|
        blk.call(channel, :stdout, "fo")
        blk.call(channel, :stdout, "o\nbar\n")
      end

      lines = []
      subject.stream_lines(ssh) do |entry|
        lines << entry.message
      end

      expect(lines).to eq(["foo\n", "bar\n"])
    end
  end
end

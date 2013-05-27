require "spec_helper"

describe CFTools::Tunnel::LogEntry do
  let(:label) { "some-label" }
  let(:line) { "something happened!" }
  let(:stream) { :stdout }

  subject { described_class.new(label, line, stream) }

  describe "#label" do
    let(:label) { "some-label" }

    it "returns the label of the entry" do
      expect(subject.label).to eq("some-label")
    end
  end

  describe "#line" do
    let(:line) { "something happened!" }

    it "returns the line of the entry" do
      expect(subject.line).to eq("something happened!")
    end
  end

  describe "#stream" do
    let(:stream) { :stdout }

    it "returns the stream of the entry" do
      expect(subject.stream).to eq(:stdout)
    end
  end

  describe "#message" do
    context "when the line is JSON" do
      let(:line) { '{"message":"foo"}' }

      it "return its 'message' field" do
        expect(subject.message).to eq("foo")
      end
    end

    context "when the line is NOT JSON" do
      let(:line) { "bar" }

      it "returns the line" do
        expect(subject.message).to eq("bar")
      end
    end
  end

  describe "#log_level" do
    context "when the line is JSON" do
      let(:line) { '{"log_level":"debug"}' }

      it "return its 'log_level' field" do
        expect(subject.log_level).to eq("debug")
      end
    end

    context "when the line is NOT JSON" do
      let(:line) { "bar" }

      it "returns nil" do
        expect(subject.log_level).to be_nil
      end
    end
  end

  describe "#timestamp" do
    let(:time) { Time.now }

    around { |example| Timecop.freeze(&example) }

    context "when the line is JSON" do
      context "and the timestamp is a string" do
        let(:line) { %Q[{"timestamp":"#{time.strftime("%F %T")}"}] }

        it "return its parsed 'timestamp' field" do
          expect(subject.timestamp.to_s).to eq(time.to_s)
        end
      end

      context "and the timestamp is numeric" do
        let(:line) { %Q[{"timestamp":#{time.to_f}}] }

        it "interprets it as time since UNIX epoch" do
          expect(subject.timestamp.to_s).to eq(time.to_s)
        end
      end

      context "and the timestamp is missing" do
        let(:line) { %Q[{}] }

        it "returns the time at which the entry was created" do
          expect(subject.timestamp).to eq(time)
        end
      end
    end

    context "when the line is NOT JSON" do
      let(:line) { "bar" }

      it "returns the time at which the entry was created" do
        expect(subject.timestamp).to eq(time)
      end
    end
  end
end

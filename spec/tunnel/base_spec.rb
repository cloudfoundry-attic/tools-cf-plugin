require "spec_helper"

module CFTools::Tunnel
  describe Base do
    before { subject.stub(:input => {:quiet => true}) }

    describe "#director" do
      context "when the given director is accessible" do
        before do
          subject.stub(:address_reachable?).with("some-director.com", 25555).and_return(true)
        end

        it "returns the given director" do
          director = subject.director("some-director.com", nil)
          expect(director.director_uri.host).to eq("some-director.com")
          expect(director.director_uri.port).to eq(25555)
        end
      end

      context "when the given director is inaccessible" do
        before do
          subject.stub(:address_reachable?).with("some-director.com", 25555).and_return(false)
        end

        it "opens a tunnel through the gateway" do
          expect(subject).to receive(:tunnel_to).with("some-director.com", 25555, "user@some-gateway") do
            1234
          end

          director = subject.director("some-director.com", "user@some-gateway")
          expect(director.director_uri.host).to eq("127.0.0.1")
          expect(director.director_uri.port).to eq(1234)
        end
      end
    end

    describe "#login_to_director" do
      let(:director) { double }

      before do
        director.stub(:user=)
        director.stub(:password=)
        director.stub(:authenticated? => true)
      end

      it "assigns the given user/pass on the director" do
        expect(director).to receive(:user=).with("user")
        expect(director).to receive(:password=).with("pass")
        subject.login_to_director(director, "user", "pass")
      end

      it "returns true iff director.authenticated?" do
        expect(director).to receive(:authenticated?).and_return(true)
        expect(subject.login_to_director(director, "user", "pass")).to be_true
      end

      it "returns false iff !director.authenticated?" do
        expect(director).to receive(:authenticated?).and_return(false)
        expect(subject.login_to_director(director, "user", "pass")).to be_false
      end
    end

    describe "#tunnel_to" do
      let(:gateway) { double }

      before { gateway.stub(:open) }

      it "creates a gateway using the given user/host" do
        expect(Net::SSH::Gateway).to receive(:new).with("ghost", "guser") { gateway }
        subject.tunnel_to("1.2.3.4", 1234, "guser@ghost")
      end

      it "opens a local tunnel and returns its port" do
        Net::SSH::Gateway.stub(:new).with("ghost", "guser") { gateway }
        expect(gateway).to receive(:open).with("1.2.3.4", 1234) { 5678 }
        expect(subject.tunnel_to("1.2.3.4", 1234, "guser@ghost")).to eq(5678)
      end
    end

    describe "#authenticate_with_director" do
      let(:director) { double }

      def self.it_asks_interactively
        it "asks for the credentials interactively" do
          if saved_credentials
            expect(subject).to receive(:login_to_director).with(director, "user", "pass").and_return(false).ordered
          end

          should_ask("Director Username") { "fizz" }
          should_ask("Director Password", anything) { "buzz" }

          expect(subject).to receive(:login_to_director).with(director, "fizz", "buzz").and_return(true).ordered

          subject.authenticate_with_director(director, "foo", saved_credentials)
        end

        context "when the interactive user/pass is valid" do
          it "returns true" do
            if saved_credentials
              expect(subject).to receive(:login_to_director).with(director, "user", "pass").and_return(false).ordered
            end

            should_ask("Director Username") { "fizz" }
            should_ask("Director Password", anything) { "buzz" }

            expect(subject).to receive(:login_to_director).with(director, "fizz", "buzz").and_return(true).ordered

            expect(
              subject.authenticate_with_director(director, "foo", saved_credentials)
            ).to be_true
          end

          it "saves them to the bosh config" do
            if saved_credentials
              expect(subject).to receive(:login_to_director).with(director, "user", "pass").and_return(false).ordered
            end

            should_ask("Director Username") { "fizz" }
            should_ask("Director Password", anything) { "buzz" }

            expect(subject).to receive(:login_to_director).with(director, "fizz", "buzz").and_return(true).ordered

            expect(subject).to receive(:save_auth).with("foo", "username" => "fizz", "password" => "buzz")

            subject.authenticate_with_director(director, "foo", saved_credentials)
          end
        end

        context "when the interactive user/pass is invalid" do
          it "asks again" do
            if saved_credentials
              expect(subject).to receive(:login_to_director).with(director, "user", "pass").and_return(false).ordered
            end

            should_ask("Director Username") { "fizz" }
            should_ask("Director Password", anything) { "buzz" }

            expect(subject).to receive(:login_to_director).with(director, "fizz", "buzz").and_return(false).ordered

            should_ask("Director Username") { "a" }
            should_ask("Director Password", anything) { "b" }

            expect(subject).to receive(:login_to_director).with(director, "a", "b").and_return(true).ordered

            subject.authenticate_with_director(director, "foo", saved_credentials)
          end
        end
      end

      context "when saved credentials are given" do
        let(:saved_credentials) { { "username" => "user", "password" => "pass" } }

        context "and they are valid" do
          it "returns true" do
            expect(subject).to receive(:login_to_director).with(director, "user", "pass").and_return(true)

            expect(
              subject.authenticate_with_director(
                director, "foo", "username" => "user", "password" => "pass")
            ).to be_true
          end
        end

        context "and they are NOT valid" do
          it_asks_interactively
        end
      end

      context "when auth credentials are NOT given" do
        let(:saved_credentials) { nil }

        it_asks_interactively
      end
    end
  end
end

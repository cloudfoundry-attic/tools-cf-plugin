require "spec_helper"

module CFTools::Tunnel
  describe Base do
    before do
      stub(subject).input { { :quiet => true } }
    end

    describe "#director" do
      context "when the given director is accessible" do
        before do
          stub(subject).address_reachable?("some-director.com", 25555) { true }
        end

        it "returns the given director" do
          director = subject.director("some-director.com", nil)
          expect(director.director_uri.host).to eq("some-director.com")
          expect(director.director_uri.port).to eq(25555)
        end
      end

      context "when the given director is inaccessible" do
        before do
          stub(subject).address_reachable?("some-director.com", 25555) { false }
        end

        it "opens a tunnel through the gateway" do
          mock(subject).tunnel_to("some-director.com", 25555, "user@some-gateway") do
            1234
          end

          director = subject.director("some-director.com", "user@some-gateway")
          expect(director.director_uri.host).to eq("127.0.0.1")
          expect(director.director_uri.port).to eq(1234)
        end
      end
    end

    describe "#login_to_director" do
      let(:director) { stub }

      before do
        stub(director).user = anything
        stub(director).password = anything
        stub(director).authenticated? { true }
      end

      it "assigns the given user/pass on the director" do
        mock(director).user = "user"
        mock(director).password = "pass"
        subject.login_to_director(director, "user", "pass")
      end

      it "returns true iff director.authenticated?" do
        mock(director).authenticated? { true }
        expect(subject.login_to_director(director, "user", "pass")).to be_true
      end

      it "returns false iff !director.authenticated?" do
        mock(director).authenticated? { false }
        expect(subject.login_to_director(director, "user", "pass")).to be_false
      end
    end

    describe "#tunnel_to" do
      let(:gateway) { stub }

      before do
        stub(gateway).open
      end

      it "creates a gateway using the given user/host" do
        mock(Net::SSH::Gateway).new("ghost", "guser") { gateway }
        subject.tunnel_to("1.2.3.4", 1234, "guser@ghost")
      end

      it "opens a local tunnel and returns its port" do
        stub(Net::SSH::Gateway).new("ghost", "guser") { gateway }
        mock(gateway).open("1.2.3.4", 1234) { 5678 }
        expect(subject.tunnel_to("1.2.3.4", 1234, "guser@ghost")).to eq(5678)
      end
    end

    describe "#authenticate_with_director" do
      let(:director) { stub }

      def self.it_asks_interactively
        it "asks for the credentials interactively" do
          if saved_credentials
            mock(subject).login_to_director(director, "user", "pass") { false }.ordered
          end

          mock_ask("Director Username") { "fizz" }.ordered
          mock_ask("Director Password", anything) { "buzz" }.ordered

          mock(subject).login_to_director(director, "fizz", "buzz") { true }.ordered

          subject.authenticate_with_director(director, "foo", saved_credentials)
        end

        context "when the interactive user/pass is valid" do
          it "returns true" do
            if saved_credentials
              mock(subject).login_to_director(director, "user", "pass") { false }.ordered
            end

            mock_ask("Director Username") { "fizz" }.ordered
            mock_ask("Director Password", anything) { "buzz" }.ordered

            mock(subject).login_to_director(director, "fizz", "buzz") { true }.ordered

            expect(
              subject.authenticate_with_director(director, "foo", saved_credentials)
            ).to be_true
          end

          it "saves them to the bosh config" do
            if saved_credentials
              mock(subject).login_to_director(director, "user", "pass") { false }.ordered
            end

            mock_ask("Director Username") { "fizz" }.ordered
            mock_ask("Director Password", anything) { "buzz" }.ordered

            mock(subject).login_to_director(director, "fizz", "buzz") { true }.ordered

            mock(subject).save_auth("foo", "username" => "fizz", "password" => "buzz")

            subject.authenticate_with_director(director, "foo", saved_credentials)
          end
        end

        context "when the interactive user/pass is invalid" do
          it "asks again" do
            if saved_credentials
              mock(subject).login_to_director(director, "user", "pass") { false }.ordered
            end

            mock_ask("Director Username") { "fizz" }.ordered
            mock_ask("Director Password", anything) { "buzz" }.ordered

            mock(subject).login_to_director(director, "fizz", "buzz") { false }.ordered

            mock_ask("Director Username") { "a" }.ordered
            mock_ask("Director Password", anything) { "b" }.ordered

            mock(subject).login_to_director(director, "a", "b") { true }.ordered

            subject.authenticate_with_director(director, "foo", saved_credentials)
          end
        end
      end

      context "when saved credentials are given" do
        let(:saved_credentials) { { "username" => "user", "password" => "pass" } }

        context "and they are valid" do
          it "returns true" do
            mock(subject).login_to_director(director, "user", "pass") { true }

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

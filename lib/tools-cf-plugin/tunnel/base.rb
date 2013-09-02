require "yaml"
require "net/ssh/gateway"

require "cf/cli"

module CFTools
  module Tunnel
    class Base < CF::CLI
      BOSH_CONFIG = "~/.bosh_config"

      def precondition
        require "cli"
      end

      def director(director_host, gateway)
        if address_reachable?(director_host, 25555)
          director_for(25555, director_host)
        else
          dport =
            with_progress("Opening local tunnel to director") do
              tunnel_to(director_host, 25555, gateway)
            end

          director_for(dport)
        end
      end

      def connected_director(director_host, gateway)
        director = director(director_host, gateway)

        authenticate_with_director(
          director,
          "https://#{director_host}:25555",
          director_credentials(director_host))

        director
      end

      def authenticate_with_director(director, remote_director, auth)
        if auth && login_to_director(director, auth["username"], auth["password"])
          return true
        end

        while true
          line unless quiet?
          user = ask("Director Username")
          pass = ask("Director Password", :echo => "*", :forget => true)
          break if login_to_director(director, user, pass)
        end

        save_auth(remote_director, "username" => user, "password" => pass)

        true
      end

      def login_to_director(director, user, pass)
        director.user = user
        director.password = pass

        with_progress("Authenticating as #{c(user, :name)}") do |s|
          director.authenticated? || s.fail
        end
      end

      def tunnel_to(address, remote_port, gateway)
        user, host = gateway.split("@", 2)
        Net::SSH::Gateway.new(host, user).open(address, remote_port)
      end

      def current_deployment(director)
        deployments =
          with_progress("Getting deployments") do
            director.list_deployments
          end

        fail "No deployments." if deployments.empty?

        cf_deployments = deployments.select do |d|
          d["releases"].any? { |r| ["cf-release", "cf"].include?(r["name"]) }
        end

        return cf_deployments.first if cf_deployments.size == 1

        ask("Which deployment?",
            :choices => deployments,
            :display => proc { |x| x["name"] })
      end

      private

      def address_reachable?(host, port)
        Timeout.timeout(1) do
          TCPSocket.new(host, port).close
          true
        end
      rescue Timeout::Error, Errno::ECONNREFUSED
        false
      end

      def director_for(port, host = "127.0.0.1")
        Bosh::Cli::Director.new("https://#{host}:#{port}")
      end

      def director_credentials(director)
        return unless cfg = bosh_config

        _, auth = cfg["auth"].find do |d, _|
          d.include?(director)
        end

        auth
      end

      def current_deployment_manifest(director)
        deployment = current_deployment(director)

        with_progress("Downloading #{c(deployment["name"], :name)} manifest") do
          YAML.load(director.get_deployment(deployment["name"])["manifest"])
        end
      end

      def save_auth(director, auth)
        cfg = bosh_config || { "auth" => {} }

        cfg["auth"][director] = auth

        save_bosh_config(cfg)
      end

      def save_bosh_config(config)
        File.open(bosh_config_file, "w") do |io|
          io.write(YAML.dump(config))
        end
      end

      def bosh_config
        return unless File.exists?(bosh_config_file)

        YAML.load_file(bosh_config_file)
      end

      def bosh_config_file
        File.expand_path(BOSH_CONFIG)
      end
    end
  end
end

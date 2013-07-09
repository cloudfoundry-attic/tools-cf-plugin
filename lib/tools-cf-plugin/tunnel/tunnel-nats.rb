require "yaml"
require "net/ssh"

require "cf/cli"

require "tools-cf-plugin/tunnel/base"

module CFTools::Tunnel
  class TunnelNATS < Base
    def self.command_by_name
      proc do |name|
        @@commands[name.gsub("-", "_").to_sym] || \
          fail("Unknown command '#{name}'.")
      end
    end

    desc "Invoke another command with a local tunnel to a remote NATS."
    input :director, :argument => :required, :desc => "BOSH director address"
    input :command, :argument => :required, :from_given => command_by_name,
          :desc => "Command to invoke"
    input :args, :argument => :splat, :desc => "Arguments for wrapped command"
    input :gateway, :default => proc { "vcap@#{input[:director]}" },
          :desc => "SSH connection string (default: vcap@director)"
    def tunnel_nats
      command = input[:command]
      director_host = input[:director]
      gateway = input[:gateway]
      args = input[:args]

      director = connected_director(director_host, gateway)

      line "Director: #{director.director_uri}"

      manifest =
        with_progress("Downloading deployment manifest") do
          current_deployment_manifest(director)
        end

      nats = manifest["properties"]["nats"]

      nport =
        with_progress("Opening local tunnel to NATS") do
          tunnel_to(nats["address"], nats["port"], gateway)
        end

      with_progress("Logging in as admin user") do
        login_as_admin(manifest)
      end

      line "NATS connection: nats://#{nats["user"]}:#{nats["password"]}@127.0.0.1:#{nport}"

      execute(
        command,
        args + %W[
          --user #{nats["user"]}
          --password #{nats["password"]}
          --port #{nport}
        ],
        input.global)
    end

    private

    def login_as_admin(manifest)
      admin = manifest["properties"]["uaa"]["scim"]["users"].grep(/cloud_controller\.admin/).first
      admin_user, admin_pass, _ = admin.split("|", 3)

      @@client = CFoundry::V2::Client.new(manifest["properties"]["cc"]["srv_api_uri"])
      @@client.login(admin_user, admin_pass)
    end
  end
end

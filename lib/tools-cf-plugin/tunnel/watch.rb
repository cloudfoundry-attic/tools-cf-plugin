require "yaml"
require "cli"
require "net/ssh"

require "cf/cli"

require "tools-cf-plugin/tunnel/base"

module CFTools::Tunnel
  class Watch < Base
    desc "Watch, by grabbing the connection info from your BOSH deployment."
    input :director, :argument => :required, :desc => "BOSH director address"
    input :gateway, :argument => :optional, 
          :default => proc { "vcap@#{input[:director]}" },
          :desc => "SSH connection string (default: vcap@director)"
    def tunnel_watch
      director_host = input[:director]
      gateway = input[:gateway]

      director = connected_director(director_host, gateway)

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

      invoke :watch, :port => nport,
             :user => nats["user"], :password => nats["password"]
    end

    private

    def login_as_admin(manifest)
      admin = manifest["properties"]["uaa"]["scim"]["users"].grep(/cloud_controller\.admin/).first
      admin_user, admin_pass, _ = admin.split("|", 3)

      @@client = CFoundry::V2::Client.new(manifest["properties"]["cc"]["srv_api_uri"])
      client.login(admin_user, admin_pass)
    end
  end
end

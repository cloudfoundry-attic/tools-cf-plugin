require "cf/cli"
require "nats/client"

module CFTools
  class AppPlacement < CF::App::Base
    def precondition; end

    desc "Show placement of running applications."
    group :admin
    input :host, :alias => "-h", :default => "127.0.0.1",
          :desc => "NATS server address"
    input :port, :alias => "-P", :default => 4222, :type => :integer,
          :desc => "NATS server port"
    input :user, :alias => "-u", :default => "nats",
          :desc => "NATS server user"
    input :password, :alias => "-p", :default => "nats",
          :desc => "NATS server password"
    input :time, :alias => "-t", :default => 12,
          :desc => "Seconds to watch heartbeats"
    def app_placement
      host = input[:host]
      port = input[:port]
      user = input[:user]
      pass = input[:password]

      render_apps(
        "nats://#{user}:#{pass}@#{host}:#{port}",
        input[:time]
      )
    end

    private
    def render_apps(uri, seconds_to_watch, options = {})
      NATS.start(:uri => uri) do
        NATS.subscribe("dea.heartbeat") do |msg|
          payload = JSON.parse(msg)
          dea_id = payload["dea"].to_i
          register_heartbeat(dea_id, payload["droplets"])
        end

        EM.add_timer(seconds_to_watch) do
          NATS.stop
        end
      end

      render_table
    rescue NATS::ServerError => e
      if e.to_s =~ /connection dropped/i
        line c("dropped by server; reconnecting...", :error)
        retry
      else
        raise
      end
    end

    def register_heartbeat(dea_id, droplets)
      note_max_dea_id(dea_id)

      app_id_to_num_instances = Hash.new(0)
      droplets.each do |droplet|
        next unless droplet["state"] == "RUNNING"
        app_id = droplet["droplet"]
        app_id_to_num_instances[app_id] += 1
      end

      app_id_to_num_instances.each do |app_id, num_instances|
        apps[app_id] ||= {}
        apps[app_id][dea_id] = num_instances
      end
    end

    def apps
      @apps ||= {}
    end

    def note_max_dea_id(dea_id)
      @max_dea_id = [@max_dea_id || 0, dea_id.to_i].max
    end

    def max_dea_id
      @max_dea_id ||= 0
    end

    def render_table
      print("%-36s placement\n" % "guid")
      apps.each do |app_id, dea_id_to_num_instances|
        placements = []
        0.upto(max_dea_id) do |dea_id|
          placements << "#{dea_id}:#{dea_id_to_num_instances.fetch(dea_id, "?")}"
        end

        print("%-36s %s\n" % [app_id, placements.join(" ")])
      end
    end
  end
end

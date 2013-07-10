require "cf/cli"
require "nats/client"
require "set"

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
    def apps
      @apps ||= {}
    end

    def known_app_ids
      @known_app_ids ||= Set.new
    end

    def known_dea_ids
      @known_dea_ids ||= Set.new
    end

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

      fill_in_zeros
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
      known_dea_ids << dea_id
      app_id_to_num_instances = Hash.new(0)
      droplets.each do |droplet|
        next unless droplet["state"] == "RUNNING"
        app_id = droplet["droplet"]
        app_id_to_num_instances[app_id] += 1

        known_app_ids << app_id
      end

      app_id_to_num_instances.each do |app_id, num_instances|
        apps[app_id] ||= {}
        apps[app_id][dea_id] = num_instances
      end
    end

    def fill_in_zeros
      known_app_ids.each do |app_id|
        known_dea_ids.each do |dea_id|
          apps[app_id][dea_id] ||= 0
        end
      end
    end

    def render_table
      print("%-36s placement\n" % "guid")
      apps.each do |app_id, dea_id_to_num_instances|
        render_app(app_id, dea_id_to_num_instances)
      end

      render_total
    end

    def render_app(app_id, dea_id_to_num_instances)
      placements = []
      0.upto(known_dea_ids.max) do |dea_id|
        placements << "#{dea_id}:#{dea_id_to_num_instances.fetch(dea_id, "?")}"
      end

      print("%-36s %s\n" % [app_id, placements.join(" ")])
    end

    def render_total
      totals = []
      0.upto(known_dea_ids.max) do |dea_id|
        if known_dea_ids.include?(dea_id)
          total_for_dea = 0

          apps.each do |app_id, dea_id_to_num_instances|
            total_for_dea += dea_id_to_num_instances[dea_id]
          end
          totals << "#{dea_id}:#{total_for_dea}"
        else
          totals << "#{dea_id}:?"
        end
      end
      print("%-36s %s\n" % ["total", totals.join(" ")])
    end
  end
end

require "cf/cli"
require "nats/client"

module CFTools
  class DEAApps < CF::App::Base
    def precondition; end

    desc "Show an overview of DEA advertisements over time."
    group :admin
    input :host, :alias => "-h", :default => "127.0.0.1",
          :desc => "NATS server address"
    input :port, :alias => "-P", :default => 4222, :type => :integer,
          :desc => "NATS server port"
    input :user, :alias => "-u", :default => "nats",
          :desc => "NATS server user"
    input :password, :alias => "-p", :default => "nats",
          :desc => "NATS server password"
    input :location, :alias => "-l", :default => false,
          :desc => "Include application's location (org/space) in table"
    def dea_apps
      host = input[:host]
      port = input[:port]
      user = input[:user]
      pass = input[:password]

      render_apps(
        "nats://#{user}:#{pass}@#{host}:#{port}",
        :include_location => input[:location])
    end

    private

    def render_apps(uri, options = {})
      NATS.start(:uri => uri) do
        NATS.subscribe("dea.advertise") do |msg|
          payload = JSON.parse(msg)
          dea_id = payload["id"]
          advertisements[dea_id] = payload["app_id_to_count"]
        end

        EM.add_periodic_timer(3) do
          render_table(options)
        end
      end
    rescue NATS::ServerError => e
      if e.to_s =~ /slow consumer/i
        line c("dropped by server; reconnecting...", :error)
        retry
      end
    end

    def seen_apps
      @seen_apps ||= {}
    end

    def advertisements
      @advertisements ||= {}
    end

    def client_app(guid)
      existing_app =
        if seen_apps.key?(guid)
          seen_apps[guid]
        else
          app = client.app(guid, :depth => 2)
          app if app.exists?
        end

      seen_apps[guid] = existing_app
    end

    def render_table(options = {})
      include_location = options[:include_location]

      app_counts = Hash.new(0)
      app_deas = Hash.new { |h, k| h[k] = [] }

      advertisements.each do |dea_id, counts|
        counts.each do |app_guid, count|
          app_counts[app_guid] += count
          app_deas[app_guid] << dea_id
        end
      end

      columns = %w[dea app guid reserved math]
      columns << "org/space" if include_location

      rows = app_counts.sort_by { |app_guid, count|
        app = client_app(app_guid)
        app ? app.memory * count : 0
      }.reverse.collect do |app_guid, count|
        app = client_app(app_guid)

        deas = list(app_deas[app_guid].collect(&:to_i).sort)

        row =
          if app
            [
              "#{b(deas)}",
              "#{c(app.name, :name)}",
              "#{app.guid}",
              "#{human_mb(app.memory * count)}",
              "(#{human_mb(app.memory)} x #{count})"
            ]
          else
            [
              "#{b(deas)}",
              c("unknown", :warning),
              "#{app_guid}",
              "?",
              "(? x #{count})"
            ]
          end

        if include_location && app
          row << "#{c(app.space.organization.name, :name)} / #{c(app.space.name, :name)}"
        end

        row
      end

      table(
        columns,
        rows)
    end

    def human_mb(mem)
      human_size(mem * 1024 * 1024)
    end

    def human_size(num, precision = 0)
      abs = num.abs

      sizes = %w(T G M K)
      sizes.each.with_index do |suf, i|
        pow = sizes.size - i
        unit = 1024.0 ** pow
        if abs >= unit
          return format("%.#{precision}f%s", num / unit, suf)
        end
      end

      format("%.#{precision}fB", num)
    end

    def list(vals)
      if vals.empty?
        d("none")
      else
        vals.join(",")
      end
    end
  end
end

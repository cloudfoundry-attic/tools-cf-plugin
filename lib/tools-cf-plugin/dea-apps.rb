require "cf/cli"
require "nats/client"

module CFTools
  class DEAApps < CF::App::Base
    def precondition; end

    desc "Show an overview of running applications."
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
          :desc => "Include application's location (org/space)"
    input :stats, :alias => "-s", :default => false,
          :desc => "Include application's runtime stats"
    def dea_apps
      host = input[:host]
      port = input[:port]
      user = input[:user]
      pass = input[:password]

      render_apps(
        "nats://#{user}:#{pass}@#{host}:#{port}",
        :include_location => input[:location],
        :include_stats => input[:stats])
    end

    private

    def render_apps(uri, options = {})
      NATS.start(:uri => uri) do
        NATS.subscribe("dea.heartbeat") do |msg|
          payload = JSON.parse(msg)
          dea_id = payload["dea"]
          register_heartbeat(dea_id, payload["droplets"])
        end

        EM.add_periodic_timer(3) do
          render_table(options)
        end
      end
    rescue NATS::ServerError => e
      if e.to_s =~ /slow consumer/i
        line c("dropped by server; reconnecting...", :error)
        retry
      else
        lien c("server error: #{e}", :error)
      end
    end

    def register_heartbeat(dea, droplets)
      heartbeats[dea] ||= {}

      droplets.each do |droplet|
        if %w[RUNNING STARTING STOPPING].include?(droplet["state"])
          heartbeats[dea][droplet["instance"]] = droplet
        else
          heartbeats[dea].delete(droplet["instance"])
        end
      end
    end

    def seen_apps
      @seen_apps ||= {}
    end

    def heartbeats
      @heartbeats ||= {}
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
      include_stats = options[:include_stats]

      app_counts = Hash.new(0)
      app_deas = Hash.new { |h, k| h[k] = [] }

      heartbeats.each do |dea_id, droplets|
        droplets.each_value do |droplet|
          app_guid = droplet["droplet"]
          app_counts[app_guid] += 1
          app_deas[app_guid] << dea_id
        end
      end

      columns = %w[dea app guid reserved math]

      columns << "stats" if include_stats
      columns << "org/space" if include_location

      rows = app_counts.sort_by { |app_guid, count|
        if seen_apps.key?(app_guid)
          app = client_app(app_guid)
          app ? app.memory * count : 0
        else
          0
        end
      }.reverse.collect do |app_guid, count|
        proc do
          app = client_app(app_guid)

          deas = list(app_deas[app_guid].collect(&:to_i).sort)

          row =
            if app
              [
                "#{b(deas)}",
                "#{c(app.name, :name)}",
                "#{app.guid}",
                "#{human_mb(app.memory * count)}",
                "(#{human_mb(app.memory)} x #{count})",
              ]
            else
              [
                "#{b(deas)}",
                c("unknown", :warning),
                "#{app_guid}",
                "?",
                "(? x #{count})",
              ]
            end

          if include_stats && app
            row << app_stats(app)
          end

          if include_location && app
            row << "#{c(app.space.organization.name, :name)} / #{c(app.space.name, :name)}"
          end

          row
        end
      end

      apps_table.render([columns] + rows)
    end

    def apps_table
      @apps_table ||= AppsTable.new
    end

    def app_stats(app)
      app.stats.sort_by(&:first).collect do |index, info|
        if info[:state] == "RUNNING"
          "%s: %0.1f%" % [index, info[:stats][:usage][:cpu] * 100]
        else
          "%s: %s" % [
            index,
            c(info[:state].downcase, state_color(info[:state]))
          ]
        end
      end.join(", ")
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

    class AppsTable
      include CF::Spacing

      def spacings
        @spacings ||= Hash.new(0)
      end

      def render(rows)
        num_columns = rows.first ? rows.first.size : 0

        rows.each do |row|
          next unless row
          row = row.call if row.respond_to?(:call)

          start_line("")

          row.each.with_index do |col, i|
            next unless col

            width = text_width(col)
            spacings[i] = width if width > spacings[i]

            if i + 1 == num_columns
              print col
            else
              print justify(col, spacings[i])
              print "   "
            end
          end

          line
        end
      end
    end
  end
end

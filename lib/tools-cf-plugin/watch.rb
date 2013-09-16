require "time"

require "cf/cli"
require "nats/client"

module CFTools
  class Watch < CF::App::Base
    def precondition; end

    # colorize if told to; don't check if output is tty
    def color?
      input[:color]
    end

    REPLY_PREFIX = "`- reply to "
    COLUMN_WIDTH = 30

    desc "Watch messages going over NATS relevant to an application"
    group :admin
    input :app, :argument => :optional, :from_given => by_name(:apps),
          :desc => "Application to watch"
    input :subjects, :aliases => %w[-s --subject],
          :from_given => proc { |s| s.split(",") },
          :desc => "NATS subject to subscribe to"
    input :host, :alias => "-h", :default => "127.0.0.1",
          :desc => "NATS server address"
    input :port, :alias => "-P", :default => 4222, :type => :integer,
          :desc => "NATS server port"
    input :user, :alias => "-u", :default => "nats",
          :desc => "NATS server user"
    input :password, :alias => "-p", :default => "nats",
          :desc => "NATS server password"
    input :logs, :alias => "-l", :desc => "NATS server logs to replay"
    def watch
      app = get_app(input[:app])
      host = input[:host]
      port = input[:port]
      user = input[:user]
      pass = input[:password]
      subjects = input[:subjects] || [">"]

      @requests = {}
      @seen_apps = {}
      @request_ticker = 0

      $stdout.sync = true

      watching_nats(
          :uri => "nats://#{user}:#{pass}@#{host}:#{port}",
          :logs => input[:logs],
          :subjects => subjects) do |msg, reply, sub, time|
        begin
          time ||= Time.now.strftime("%r")

          if @requests.include?(sub)
            process_response(sub, reply, msg, app, time)
          elsif !app || msg.include?(app.guid)
            process_message(sub, reply, msg, app, time)
          end
        rescue => e
          line c("couldn't deal w/ #{sub} '#{msg}': #{e.class}: #{e}", :error)
        end
      end
    end

    private

    def list(vals)
      if vals.empty?
        d("none")
      else
        vals.join(", ")
      end
    end

    def process_message(sub, reply, msg, app, time)
      register_request(sub, reply) if reply

      payload = JSON.parse(msg) rescue msg

      case sub
      when "dea.advertise"
        return if app
        sub, payload = pretty_dea_advertise(sub, payload)
      when "staging.advertise"
        return if app
        sub, payload = pretty_staging_advertise(sub, payload)
      when "droplet.exited"
        sub, payload = pretty_exited(sub, payload)
      when "dea.heartbeat"
        sub, payload = pretty_heartbeat(sub, payload, app)
      when "router.start"
        sub, payload = pretty_router_start(sub, payload)
      when "router.register"
        sub, payload = pretty_register(sub, payload)
      when "router.unregister"
        sub, payload = pretty_unregister(sub, payload)
      when /^dea\.(\d+)-.*\.start$/
        sub, payload = pretty_start(payload, $1)
      when "dea.stop"
        sub, payload = pretty_stop(sub, payload)
      when "droplet.updated"
        sub, payload = pretty_updated(sub, payload)
      when "dea.update"
        sub, payload = pretty_dea_update(sub, payload)
      when "dea.find.droplet"
        sub, payload = pretty_find_droplet(sub, payload)
      when "healthmanager.status"
        sub, payload = pretty_healthmanager_status(sub, payload)
      when "healthmanager.health"
        sub, payload = pretty_healthmanager_health(sub, payload)
      when "dea.shutdown"
        sub, payload = pretty_dea_shutdown(sub, payload)
      when "health.start"
        sub, payload = pretty_health_start(sub, payload)
      when "health.stop"
        sub, payload = pretty_health_stop(sub, payload)
      when /^([^.]+)\.announce$/
        sub, payload = pretty_service_announcement(sub, payload)
      when "vcap.component.announce"
        sub, payload = pretty_component_announcement(sub, payload)
      when "vcap.component.discover"
        sub, payload = pretty_component_discover(sub, payload)
      end

      if reply
        sub += " " * REPLY_PREFIX.size
        sub += " (#{c(@request_ticker, :error)})"
      end

      sub = sub.ljust(COLUMN_WIDTH)
      line "#{time}\t#{sub}\t#{payload}"
    end

    def process_response(sub, _, msg, _, time)
      payload = JSON.parse(msg) # rescue msg

      sub, id = @requests[sub]

      case sub
      when "dea.find.droplet"
        sub, payload = pretty_find_droplet_response(sub, payload)
      when "healthmanager.status"
        sub, payload = pretty_healthmanager_status_response(sub, payload)
      when "healthmanager.health"
        sub, payload = pretty_healthmanager_health_response(sub, payload)
      when "vcap.component.discover"
        sub, payload = pretty_component_discover_response(sub, payload)
      end

      line "#{time}\t#{REPLY_PREFIX}#{sub} (#{c(id, :error)})\t#{payload}"
    end

    def pretty_dea_advertise(sub, payload)
      dea, _ = payload["id"].split("-", 2)
      [ d(sub),
        [ "dea: #{dea}",
          "stacks: #{list(payload["stacks"])}",
          "available mem: #{human_mb(payload["available_memory"])}",
          "apps: #{pretty_app_count(payload["app_id_to_count"] || [])}"
        ].join(", ")
      ]
    end

    def pretty_staging_advertise(sub, payload)
      dea, _ = payload["id"].split("-", 2)
      [ d(sub),
        [ "dea: #{dea}",
          "stacks: #{list(payload["stacks"])}",
          "available mem: #{human_mb(payload["available_memory"])}"
        ].join(", ")
      ]
    end

    def pretty_app_count(counts)
      list(counts.collect { |g, c| "#{c} x #{pretty_app(g)}" })
    end

    def pretty_exited(sub, payload)
      [ c(sub, :bad),
        [ "app: #{pretty_app(payload["droplet"])}",
          "reason: #{payload["reason"]}",
          "index: #{payload["index"]}",
          "version: #{pretty_version(payload["version"])}"
        ].join(", ")
      ]
    end

    def pretty_heartbeat(sub, payload, app)
      dea, _ = payload["dea"].split("-", 2)

      states = Hash.new(0)
      payload["droplets"].each do |droplet|
        next unless !app || droplet["droplet"] == app.guid
        states[droplet["state"]] += 1
      end

      [ d(sub),
        "dea: #{dea}, " + states.collect { |state, count|
          "#{c(state.downcase, state_color(state))}: #{count}"
        }.join(", ")
      ]
    end

    def pretty_router_start(sub, payload)
      [c(sub, :neutral), "hosts: #{list(payload["hosts"])}"]
    end

    def pretty_register(sub, payload)
      message = []

      if (dea_id = payload["dea"])
        dea, _ = dea_id.split("-", 2)
        message += ["app: #{pretty_app(payload["app"])}", "dea: #{dea}"]
      end

      message += [
        "uris: #{list(payload["uris"])}",
        "host: #{payload["host"]}",
        "port: #{payload["port"]}"
      ]

      [c(sub, :neutral), message.join(", ")]
    end

    def pretty_unregister(sub, payload)
      message = []

      if (dea_id = payload["dea"])
        dea, _ = dea_id.split("-", 2)
        message += ["app: #{pretty_app(payload["app"])}", "dea: #{dea}"]
      end

      message += [
        "uris: #{list(payload["uris"])}",
        "host: #{payload["host"]}",
        "port: #{payload["port"]}"
      ]

      [c(sub, :warning), message.join(", ")]
    end

    def pretty_start(payload, dea)
      [ c("dea.#{dea}.start", :good),
        [ "app: #{pretty_app(payload["droplet"])}",
          "dea: #{dea}",
          "index: #{payload["index"]}",
          "version: #{pretty_version(payload["version"])}",
          "uris: #{list(Array(payload["uris"]))}"
        ].join(", ")
      ]
    end

    def pretty_stop(sub, payload)
      message = ["app: #{pretty_app(payload["droplet"])}"]

      if (version = payload["version"])
        message << "version: #{pretty_version(version)}"
      end

      if (indices = payload["indices"])
        message << "scaling down indices: #{indices.join(", ")}"
      elsif (instances = payload["instances"])
        message << "killing extra instances: #{instances.join(", ")}"
      else
        message << "stopping application"
      end

      [c(sub, :warning), message.join(", ")]
    end

    def pretty_dea_update(sub, payload)
      [ d(sub),
        [ "app: #{pretty_app(payload["droplet"])}",
          "uris: #{list(payload["uris"])}"
        ].join(", ")
      ]
    end

    def pretty_find_droplet(sub, payload)
      states = (payload["states"] || []).collect do |s|
        c(s.downcase, state_color(s))
      end

      [ d(sub),
        [ "app: #{pretty_app(payload["droplet"])}",
          "version: #{pretty_version(payload["version"])}",
          "querying states: #{list(states)}"
        ].join(", ")
      ]
    end

    def pretty_find_droplet_response(sub, payload)
      dea, _ = payload["dea"].split("-", 2)
      index = payload["index"]
      state = payload["state"]
      version = payload["version"]
      since = Time.at(payload["state_timestamp"])
      [ sub,
        [ "dea: #{dea}",
          "index: #{index}",
          "state: #{c(state.downcase, state_color(state))}",
          "version: #{pretty_version(version)}",
          "since: #{since}"
        ].join(", ")
      ]
    end

    def pretty_healthmanager_status(sub, payload)
      state = payload["state"]
      version = payload["version"]

      [ d(sub),
        [ "app: #{pretty_app(payload["droplet"])}",
          "version: #{pretty_version(version)}",
          "querying states: #{c(state.downcase, state_color(state))}"
        ].join(", ")
      ]
    end

    def pretty_healthmanager_status_response(sub, payload)
      [sub, "indices: #{list(payload["indices"])}"]
    end

    def pretty_healthmanager_health(sub, payload)
      apps = payload["droplets"].collect do |d|
        "#{pretty_app(d["droplet"])} (#{pretty_version(d["version"])})"
      end

      [d(sub), "querying health for: #{list(apps)}"]
    end

    def pretty_healthmanager_health_response(sub, payload)
      [ sub,
        [ "app: #{pretty_app(payload["droplet"])}",
          "version: #{pretty_version(payload["version"])}",
          "healthy: #{payload["healthy"]}"
        ].join(", ")
      ]
    end

    def pretty_updated(sub, payload)
      [d(sub), "app: #{pretty_app(payload["droplet"])}"]
    end

    def pretty_dea_shutdown(sub, payload)
      dea, _ = payload["id"].split("-", 2)

      apps = payload["app_id_to_count"].collect do |guid, count|
        "#{count} x #{pretty_app(guid)}"
      end

      [c(sub, :error), "dea: #{dea}, apps: #{list(apps)}"]
    end

    def pretty_health_start(sub, payload)
      [ c(sub, :good),
        [ "app: #{pretty_app(payload["droplet"])}",
          "version: #{pretty_version(payload["version"])}",
          "indices: #{list(payload["indices"])}",
          "running: #{pretty_running_counts(payload["running"])}"
        ].join(", ")
      ]
    end

    def pretty_health_stop(sub, payload)
      [ c(sub, :bad),
        [ "app: #{pretty_app(payload["droplet"])}",
          "instances: #{pretty_instance_breakdown(payload["instances"])}",
          "running: #{pretty_running_counts(payload["running"])}"
        ].join(", ")
      ]
    end

    def pretty_service_announcement(sub, payload)
      id = payload["id"]
      plan = payload["plan"]
      c_unit = payload["capacity_unit"]
      c_max = payload["max_capacity"]
      c_avail = payload["available_capacity"]
      s_versions = payload["supported_versions"]

      [ d(sub),
        [ "id: #{id}",
          "plan: #{plan}",
          "supported versions: #{list(s_versions)}",
          "capacity: (available: #{c_avail}, max: #{c_max}, unit: #{c_unit})"
        ].join(", ")
      ]
    end

    def pretty_component_announcement(sub, payload)
      type = payload["type"]
      index = payload["index"]
      uuid = payload["uuid"]
      time = payload["start"]

      [ d(sub),
        [ "type: #{type}",
          "index: #{index}",
          "uuid: #{uuid}",
          "start time: #{time}"
        ].join(", ")
      ]
    end

    def pretty_component_discover(sub, payload)
      [d(sub), payload]
    end

    def pretty_component_discover_response(sub, payload)
      type = payload["type"]
      index = payload["index"]
      host = payload["host"]
      user, pass = payload["credentials"]
      uptime = payload["uptime"]

      message = [
        "type: #{type}",
        "index: #{index}",
        "uri: #{user}:#{pass}@#{host}"
      ]

      message << "uptime: #{uptime}" if uptime

      [d(sub), message.join(", ")]
    end

    def pretty_running_counts(running)
      running.collect do |ver, num|
        "#{num} x #{pretty_version(ver)}"
      end.join(", ")
    end

    def pretty_instance_breakdown(instances)
      instances.collect do |inst, ver|
        "#{inst} (#{pretty_version(ver)})"
      end.join(", ")
    end

    def pretty_version(guid)
      if guid
        guid.split("-").first
      else
        d("none")
      end
    end

    def pretty_app(guid)
      return guid unless client

      existing_app =
        if @seen_apps.key?(guid)
          @seen_apps[guid]
        else
          app = client.app(guid)
          app if app.exists?
        end

      if existing_app
        @seen_apps[guid] = existing_app
        c(existing_app.name, :name)
      else
        @seen_apps[guid] = nil
        d("unknown (#{guid})")
      end
    rescue CFoundry::TargetRefused, CFoundry::InvalidAuthToken
      guid
    end

    def watching_nats(options, &blk)
      if options[:logs]
        logs = Dir[File.expand_path(options[:logs])]

        logs.each do |log|
          File.open(log) do |io|
            io.each do |line|
              dispatch_line(line, options[:subjects], &blk)
            end
          end
        end
      else
        begin
          NATS.start(:uri => options[:uri]) do
            options[:subjects].each do |subject|
              NATS.subscribe(subject, &blk)
            end
          end
        rescue NATS::ServerError => e
          if e.to_s =~ /slow consumer/i
            line c("dropped by server; reconnecting...", :error)
            retry
          end
        end
      end
    end

    def dispatch_line(line, subjects)
      matches = line.match(/^([^ ]+) \[#\d+\] Received on \[([^\]]+)\] : '(.*)'$/)
      timestamp = matches[1]
      subject = matches[2]
      message = matches[3]

      return unless subjects.any? { |p| subject_matches?(subject, p) }

      gmt = Time.parse("#{timestamp} GMT")
      yield message, nil, subject, gmt.strftime("%Y-%m-%d %r")
    end

    def subject_matches?(subject, pattern)
      ssegs = subject.split(".")
      psegs = pattern.split(".")

      # match sizes because zip is silly
      ssegs[psegs.size - 1] ||= nil

      ssegs.zip(psegs) do |a, b|
        break if b == ">"
        return false if a == nil
        next if b == "*"
        return false if a != b
      end

      true
    end

    def register_request(sub, reply)
      @requests[reply] = [sub, @request_ticker += 1]
    end

    def get_app(apps)
      return unless apps

      if apps.empty?
        fail "Unknown app '#{input.given[:app]}'."
      elsif apps.size == 1
        apps.first
      else
        disambiguate_app(apps)
      end
    end

    def disambiguate_app(apps)
      ask("Which application?", :choices => apps,
          :display => proc do |a|
            "#{a.name} (#{a.space.organization.name}/#{a.space.name})"
          end)
    end
  end
end

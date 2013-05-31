require "cf/cli"
require "nats/client"

module CFTools
  class Watch < CF::App::Base
    def precondition
      check_target
    end

    REPLY_PREFIX = "`- reply to "
    COLUMN_WIDTH = 30

    desc "Watch messages going over NATS relevant to an application"
    group :admin
    input :app, :argument => :optional, :from_given => by_name(:app),
          :desc => "Application to watch"
    input :host, :alias => "-h", :default => "127.0.0.1",
          :desc => "NATS server address"
    input :port, :alias => "-P", :default => 4222, :type => :integer,
          :desc => "NATS server port"
    input :user, :alias => "-u", :default => "nats",
          :desc => "NATS server user"
    input :password, :alias => "-p", :default => "nats",
          :desc => "NATS server password"
    def watch
      app = input[:app]
      host = input[:host]
      port = input[:port]
      user = input[:user]
      pass = input[:password]

      @requests = {}
      @seen_apps = {}
      @request_ticker = 0

      $stdout.sync = true

      watching_nats("nats://#{user}:#{pass}@#{host}:#{port}") do |msg, reply, sub|
        begin
          if @requests.include?(sub)
            process_response(sub, reply, msg, app)
          elsif !app || msg.include?(app.guid)
            process_message(sub, reply, msg, app)
          end
        rescue => e
          line c("couldn't deal w/ #{sub} '#{msg}': #{e.class}: #{e}", :error)
        end
      end
    end

    private

    def timestamp
      Time.now.strftime("%r")
    end

    def list(vals)
      if vals.empty?
        d("none")
      else
        vals.join(", ")
      end
    end

    def process_message(sub, reply, msg, app)
      register_request(sub, reply) if reply

      case sub
      when "dea.advertise"
        return if app
        sub, msg = pretty_dea_advertise(sub, msg)
      when "staging.advertise"
        return if app
        sub, msg = pretty_staging_advertise(sub, msg)
      when "droplet.exited"
        sub, msg = pretty_exited(sub, msg)
      when "dea.heartbeat"
        sub, msg = pretty_heartbeat(sub, msg, app)
      when "router.start"
        sub, msg = pretty_router_start(sub, msg)
      when "router.register"
        return unless app
        sub, msg = pretty_register(sub, msg)
      when "router.unregister"
        sub, msg = pretty_unregister(sub, msg)
      when /^dea\.(\d+)-.*\.start$/
        sub, msg = pretty_start(sub, msg, $1)
      when "dea.stop"
        sub, msg = pretty_stop(sub, msg)
      when "droplet.updated"
        sub, msg = pretty_updated(sub, msg)
      when "dea.update"
        sub, msg = pretty_dea_update(sub, msg)
      when "dea.find.droplet"
        sub, msg = pretty_find_droplet(sub, msg)
      when "healthmanager.status"
        sub, msg = pretty_healthmanager_status(sub, msg)
      when "healthmanager.health"
        sub, msg = pretty_healthmanager_health(sub, msg)
      when "dea.shutdown"
        sub, msg = pretty_dea_shutdown(sub, msg)
      when /^cloudcontrollers\.hm\.requests\.\w+$/
        sub, msg = process_cloudcontrollers_hm_request(sub, msg)
      when /^([^.]+)\.announce$/
        sub, msg = pretty_service_announcement(sub, msg)
      when "vcap.component.announce"
        sub, msg = pretty_component_announcement(sub, msg)
      when "vcap.component.discover"
        sub, msg = pretty_component_discover(sub, msg)
      end

      if reply
        sub += " " * REPLY_PREFIX.size
        sub += " (#{c(@request_ticker, :error)})"
      end

      sub = sub.ljust(COLUMN_WIDTH)
      line "#{timestamp}\t#{sub}\t#{msg}"
    end

    def process_response(sub, _, msg, _)
      sub, id = @requests[sub]

      case sub
      when "dea.find.droplet"
        sub, msg = pretty_find_droplet_response(sub, msg)
      when "healthmanager.status"
        sub, msg = pretty_healthmanager_status_response(sub, msg)
      when "healthmanager.health"
        sub, msg = pretty_healthmanager_health_response(sub, msg)
      when "vcap.component.discover"
        sub, msg = pretty_component_discover_response(sub, msg)
      end

      line "#{timestamp}\t#{REPLY_PREFIX}#{sub} (#{c(id, :error)})\t#{msg}"
    end

    def pretty_dea_advertise(sub, msg)
      payload = JSON.parse(msg)
      dea, _ = payload["id"].split("-", 2)
      [ d(sub),
        [ "dea: #{dea}",
          "stacks: #{list(payload["stacks"])}",
          "available mem: #{human_mb(payload["available_memory"])}",
          "apps: #{pretty_app_count(payload["app_id_to_count"] || [])}"
        ].join(", ")
      ]
    end

    def pretty_staging_advertise(sub, msg)
      payload = JSON.parse(msg)
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

    def pretty_exited(sub, msg)
      payload = JSON.parse(msg)
      [ c(sub, :bad),
        [ "app: #{pretty_app(payload["droplet"])}",
          "reason: #{payload["reason"]}",
          "index: #{payload["index"]}"
        ].join(", ")
      ]
    end

    def pretty_heartbeat(sub, msg, app)
      payload = JSON.parse(msg)

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

    def pretty_router_start(sub, msg)
      payload = JSON.parse(msg)
      [c(sub, :neutral), "hosts: #{list(payload["hosts"])}"]
    end

    def pretty_register(sub, msg)
      payload = JSON.parse(msg)

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

    def pretty_unregister(sub, msg)
      payload = JSON.parse(msg)

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

    def pretty_start(sub, msg, dea)
      payload = JSON.parse(msg)
      [ c("dea.#{dea}.start", :good),
        [ "app: #{pretty_app(payload["droplet"])}",
          "dea: #{dea}",
          "index: #{payload["index"]}",
          "uris: #{list(payload["uris"])}"
        ].join(", ")
      ]
    end

    def pretty_stop(sub, msg)
      payload = JSON.parse(msg)

      message = ["app: #{pretty_app(payload["droplet"])}"]

      if (indices = payload["indices"])
        message << "scaling down indices: #{indices.join(", ")}"
      elsif (instances = payload["instances"])
        message << "killing extra instances: #{instances.join(", ")}"
      else
        message << "stopping application"
      end

      [c(sub, :warning), message.join(", ")]
    end

    def pretty_dea_update(sub, msg)
      payload = JSON.parse(msg)
      [ d(sub),
        [ "app: #{pretty_app(payload["droplet"])}",
          "uris: #{list(payload["uris"])}"
        ].join(", ")
      ]
    end

    def pretty_find_droplet(sub, msg)
      payload = JSON.parse(msg)
      states = payload["states"].collect { |s| c(s.downcase, state_color(s))}
      [ d(sub),
        [ "app: #{pretty_app(payload["droplet"])}",
          "querying states: #{states.join(", ")}"
        ].join(", ")
      ]
    end

    def pretty_find_droplet_response(sub, msg)
      payload = JSON.parse(msg)
      dea, _ = payload["dea"].split("-", 2)
      index = payload["index"]
      state = payload["state"]
      time = Time.at(payload["state_timestamp"])
      [ sub,
        [ "dea: #{dea}",
          "index: #{index}",
          "state: #{c(state.downcase, state_color(state))}",
          "since: #{time}"
        ].join(", ")
      ]
    end

    def pretty_healthmanager_status(sub, msg)
      payload = JSON.parse(msg)
      state = payload["state"]
      [ d(sub),
        [ "app: #{pretty_app(payload["droplet"])}",
          "querying states: #{c(state.downcase, state_color(state))}"
        ].join(", ")
      ]
    end

    def pretty_healthmanager_status_response(sub, msg)
      payload = JSON.parse(msg)
      [sub, "indices: #{list(payload["indices"])}"]
    end

    def pretty_healthmanager_health(sub, msg)
      payload = JSON.parse(msg)
      apps = payload["droplets"].collect { |d| pretty_app(d["droplet"]) }
      [d(sub), "querying health for: #{list(apps)}"]
    end

    def pretty_healthmanager_health_response(sub, msg)
      payload = JSON.parse(msg)
      [ sub,
        [ "app: #{pretty_app(payload["droplet"])}",
          "healthy: #{payload["healthy"]}"
        ].join(", ")
      ]
    end

    def pretty_updated(sub, msg)
      payload = JSON.parse(msg)
      [d(sub), "app: #{pretty_app(payload["droplet"])}"]
    end

    def pretty_dea_shutdown(sub, msg)
      payload = JSON.parse(msg)

      dea, _ = payload["id"].split("-", 2)

      apps = payload["app_id_to_count"].collect do |guid, count|
        "#{count} x #{pretty_app(guid)}"
      end

      [c(sub, :error), "dea: #{dea}, apps: #{list(apps)}"]
    end

    def process_cloudcontrollers_hm_request(sub, msg)
      payload = JSON.parse(msg)
      last_updated = Time.at(payload["last_updated"])

      op = payload["op"]

      message = [
        "app: #{pretty_app(payload["droplet"])}",
        "operation: #{pretty_hm_op(op)}",
        "app last updated: #{last_updated}"
      ]

      case op
      when "STOP"
        message << "instances: #{list(payload["instances"])}"
      when "START"
        message << "indices: #{list(payload["indices"])}"
      end

      [c("hm.request", :warning), message.join(", ")]
    end

    def pretty_service_announcement(sub, msg)
      payload = JSON.parse(msg)
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

    def pretty_component_announcement(sub, msg)
      payload = JSON.parse(msg)
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

    def pretty_component_discover(sub, msg)
      [d(sub), msg]
    end

    def pretty_component_discover_response(sub, msg)
      payload = JSON.parse(msg)
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

    def pretty_hm_op(op)
      case op
      when "STOP"
        c("stop", :bad)
      when "START"
        c("start", :good)
      else
        op
      end
    end

    def pretty_app(guid)
      existing_app =
        if @seen_apps.key?(guid)
          @seen_apps[guid]
        else
          app = client.app(guid)
          app if app.exists?
        end

      if existing_app
        #@seen_apps[guid] = existing_app
        c(existing_app.name, :name)
      else
        @seen_apps[guid] = nil
        d("unknown (#{guid})")
      end
    end

    def watching_nats(uri, &blk)
      NATS.start(:uri => uri) do
        NATS.subscribe(">", &blk)
      end
    end

    def register_request(sub, reply)
      @requests[reply] = [sub, @request_ticker += 1]
    end
  end
end

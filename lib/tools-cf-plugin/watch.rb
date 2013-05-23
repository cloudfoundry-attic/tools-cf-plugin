require "cf/cli"
require "nats/client"

module CFTools
  class Watch < CF::App::Base
    def precondition
      check_target
    end

    REPLY_PREFIX = "`- reply to "

    desc "Watch messages going over NATS relevant to an application"
    group :admin
    input :app, :argument => :required, :from_given => by_name(:app),
          :desc => "Application to watch"
    input :host, :alias => "-h", :default => "localhost",
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
      @request_ticker = 0

      $stdout.sync = true

      watching_nats("nats://#{user}:#{pass}@#{host}:#{port}") do |msg, reply, sub|
        begin
          if @requests.include?(sub)
            process_response(sub, reply, msg, app)
          elsif msg.include?(app.guid)
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
        return
      when "droplet.exited"
        sub, msg = pretty_exited(sub, msg)
      when "dea.heartbeat"
        sub, msg = pretty_heartbeat(sub, msg, app)
      when "router.register"
        sub, msg = pretty_register(sub, msg)
      when "router.unregister"
        sub, msg = pretty_unregister(sub, msg)
      when /^dea\.(\d+)-.*\.start$/
        sub, msg = pretty_start(sub, msg, $1)
      when "dea.stop"
        sub, msg = pretty_stop(sub, msg)
      when "droplet.updated"
        sub, msg = pretty_updated(sub)
      when "dea.update"
        sub, msg = pretty_dea_update(sub, msg)
      when "dea.find.droplet"
        sub, msg = pretty_find_droplet(sub, msg)
      when "healthmanager.status"
        sub, msg = pretty_healthmanager_status(sub, msg)
      end

      if reply
        sub += " " * REPLY_PREFIX.size
        sub += " (#{c(@request_ticker, :error)})"
      end

      line "#{timestamp}\t#{sub}\t#{msg}"
    end

    def process_response(sub, _, msg, _)
      sub, id = @requests[sub]

      case sub
      when "dea.find.droplet"
        sub, msg = pretty_find_droplet_response(sub, msg)
      when "healthmanager.status"
        sub, msg = pretty_healthmanager_status_response(sub, msg)
      end

      line "#{timestamp}\t#{REPLY_PREFIX}#{sub} (#{c(id, :error)})\t#{msg}"
    end

    def pretty_exited(sub, msg)
      payload = JSON.parse(msg)
      [ c(sub, :bad),
        "reason: #{payload["reason"]}, index: #{payload["index"]}"
      ]
    end

    def pretty_heartbeat(sub, msg, app)
      payload = JSON.parse(msg)

      states = Hash.new(0)
      payload["droplets"].each do |droplet|
        next unless droplet["droplet"] == app.guid
        states[droplet["state"]] += 1
      end

      [ d(sub),
        "dea: #{payload["dea"].to_i}, " + states.collect { |state, count|
          "#{c(state.downcase, state_color(state))}: #{count}"
        }.join(", ")
      ]
    end

    def pretty_register(sub, msg)
      payload = JSON.parse(msg)
      dea, _ = payload["dea"].split("-", 2)
      [ c(sub, :neutral),
        "dea: #{dea}, uris: #{list(payload["uris"])}, host: #{payload["host"]}, port: #{payload["port"]}"
      ]
    end

    def pretty_unregister(sub, msg)
      payload = JSON.parse(msg)
      dea, _ = payload["dea"].split("-", 2)
      [ c(sub, :warning),
        "dea: #{dea}, uris: #{list(payload["uris"])}, host: #{payload["host"]}, port: #{payload["port"]}"
      ]
    end

    def pretty_start(sub, msg, dea)
      payload = JSON.parse(msg)
      [ c("dea.#{dea}.start", :good),
        "dea: #{dea}, index: #{payload["index"]}, uris: #{list(payload["uris"])}"
      ]
    end

    def pretty_stop(sub, msg)
      payload = JSON.parse(msg)

      if (indices = payload["indices"])
        msg = "scaling down indices: #{indices.join(", ")}"
      elsif (instances = payload["instances"])
        msg = "killing extra instances: #{instances.join(", ")}"
      else
        msg = "stopping application"
      end

      [c(sub, :warning), msg]
    end

    def pretty_dea_update(sub, msg)
      payload = JSON.parse(msg)
      [d(sub), "uris: #{payload["uris"].join(", ")}"]
    end

    def pretty_find_droplet(sub, msg)
      payload = JSON.parse(msg)
      states = payload["states"].collect { |s| c(s.downcase, state_color(s))}
      [d(sub), "querying states: #{states.join(", ")}"]
    end

    def pretty_find_droplet_response(sub, msg)
      payload = JSON.parse(msg)
      dea = payload["dea"]
      index = payload["index"]
      state = payload["state"]
      time = Time.at(payload["state_timestamp"])
      [ sub,
        "dea: #{dea.to_i}, index: #{index}, state: #{c(state.downcase, state_color(state))}, since: #{time}"
      ]
    end

    def pretty_healthmanager_status(sub, msg)
      payload = JSON.parse(msg)
      state = payload["state"]
      [d(sub), "querying states: #{c(state.downcase, state_color(state))}"]
    end

    def pretty_healthmanager_status_response(sub, msg)
      payload = JSON.parse(msg)
      [sub, "indices: #{list(payload["indices"])}"]
    end

    def pretty_updated(sub)
      [d(sub), ""]
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

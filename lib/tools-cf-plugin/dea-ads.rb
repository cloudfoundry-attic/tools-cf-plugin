require "cf/cli"
require "nats/client"

module CFTools
  class DEAAds < CF::App::Base
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
    def dea_ads
      host = input[:host]
      port = input[:port]
      user = input[:user]
      pass = input[:password]

      NATS.start(:uri => "nats://#{user}:#{pass}@#{host}:#{port}") do
        NATS.subscribe("dea.advertise") do |msg|
          payload = JSON.parse(msg)
          id = payload["id"]
          prev = advertisements[id]
          advertisements[id] = [payload, prev && prev.first]
        end

        EM.add_periodic_timer(2) do
          render_table
        end
      end
    end

    private

    def advertisements
      @advertisements ||= {}
    end

    def render_table
      rows = 
        advertisements.sort.collect do |id, (attrs, prev)|
          idx, _ = id.split("-", 2)

          [ c(idx, :name),
            list(attrs["stacks"]),
            diff(attrs, prev) { |x| x["app_id_to_count"].values.inject(&:+) },
            diff(attrs, prev) { |x| x["available_memory"] }
          ]
        end

      table(["dea", "stacks", "droplets", "available memory"], rows)
    end

    def diff(curr, prev)
      new = yield curr
      old = yield prev if prev

      if !old || new == old
        new.to_s
      else
        "#{new} (#{signed(new - old)})"
      end
    end

    def signed(num)
      num > 0 ? "+#{num}" : num
    end

    def list(vals)
      if vals.empty?
        d("none")
      else
        vals.join(", ")
      end
    end
  end
end

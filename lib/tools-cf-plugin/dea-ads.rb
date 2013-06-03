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

        EM.add_periodic_timer(3) do
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
            diff(attrs, prev, :pretty_memory, :pretty_memory_diff) do |x|
              x["available_memory"]
            end
          ]
        end

      table(["dea", "stacks", "droplets", "available memory"], rows)
    end

    def diff(curr, prev, pretty = nil, pretty_diff = :signed)
      new = yield curr
      old = yield prev if prev
      diff = new - old if old

      display = pretty ? send(pretty, new) : new.to_s
      diff_display = pretty_diff ? send(pretty_diff, diff) : diff.to_s if diff

      if !old || new == old
        display
      else
        "#{display} (#{diff_display})"
      end
    end

    def signed(num)
      num > 0 ? c("+#{num}", :good) : c(num, :bad)
    end

    def pretty_memory(mem)
      human = human_mb(mem)

      if mem < 1024
        c(human, :bad)
      elsif mem < 2048
        c(human, :warning)
      else
        c(human, :good)
      end
    end

    def pretty_memory_diff(diff)
      human = human_mb(diff)

      if diff < 0
        c(human, :bad)
      else
        c("+#{human}", :good)
      end
    end

    def human_mb(mem)
      human_size(mem * 1024 * 1024)
    end

    def human_size(num, precision = 1)
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
        vals.join(", ")
      end
    end
  end
end

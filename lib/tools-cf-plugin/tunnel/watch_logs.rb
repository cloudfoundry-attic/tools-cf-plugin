require "yaml"
require "thread"

require "tools-cf-plugin/tunnel/base"
require "tools-cf-plugin/tunnel/multi_line_stream"
require "tools-cf-plugin/tunnel/stream_location"

module CFTools::Tunnel
  class WatchLogs < Base
    LOGS = {
      "cloud_controller" => ["cloud_controller_ng/cloud_controller_ng.log"],
      "dea_next" => ["dea_next/dea_next.log"],
      "health_manager" => ["health_manager_next/health_manager_next.log"],
      "router" => ["gorouter/gorouter.log"]
    }

    desc "Stream logs from the jobs of a deployment"
    input :director, :argument => :required, :desc => "BOSH director address"
    input :gateway, :argument => :optional, 
          :default => proc { "vcap@#{input[:director]}" },
          :desc => "SSH connection string (default: vcap@director)"
    def watch_logs
      director_host = input[:director]
      gateway = input[:gateway]

      director = connected_director(director_host, gateway)

      stream = stream_for(gateway)

      deployment =
        with_progress("Getting deployment info") do
          current_deployment(director)
        end

      locations =
        with_progress("Finding logs for #{c(deployment["name"], :name)}") do
          locs = stream_locations(director, deployment["name"])

          if locs.empty?
            fail "No locations found."
          else
            locs
          end
        end

      stream.stream(locations) do |entry|
        line pretty_print_entry(entry)
      end
    end

    private

    def stream_for(gateway)
      user, host = gateway.split("@", 2)
      MultiLineStream.new(user, host)
    end

    def max_label_size
      LOGS.keys.collect(&:size).sort.last + 3
    end

    def pretty_print_entry(entry)
      log_level = entry.log_level || ""
      level_padding = " " * (6 - log_level.size)
      [ c(entry.label.ljust(max_label_size), :name),
        entry.timestamp.strftime("%r"),
        "#{pretty_log_level(log_level)}#{level_padding}",
        level_colored_message(entry)
      ].join("  ")
    end

    def stream_locations(director, deployment)
      locations = Hash.new { |h, k| h[k] = [] }

      director.fetch_vm_state(deployment, :use_cache => false).each do |vm|
        name = vm["job_name"]
        index = vm["index"]
        next unless LOGS.key?(name)

        vm["ips"].each do |ip|
          LOGS[name].each do |file|
            locations[ip] << StreamLocation.new(file, "#{name}/#{index}")
          end
        end
      end

      locations
    end

    def level_colored_message(entry)
      msg = entry.message

      case entry.log_level
      when "warn"
        c(msg, :warning)
      when "error"
        c(msg, :bad)
      when "fatal"
        c(msg, :error)
      else
        msg
      end
    end

    def pretty_log_level(level)
      case level
      when "info"
        d(level)
      when "debug", "debug1", "debug2", "all"
        c(level, :good)
      when "warn"
        c(level, :warning)
      when "error"
        c(level, :bad)
      when "fatal"
        c(level, :error)
      else
        level
      end
    end
  end
end

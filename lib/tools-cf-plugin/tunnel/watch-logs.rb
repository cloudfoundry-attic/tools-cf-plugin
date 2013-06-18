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
    input :components, :argument => :splat, :desc => "Which components to log"
    input :gateway, :default => proc { "vcap@#{input[:director]}" },
          :desc => "SSH connection string (default: vcap@director)"
    def watch_logs
      director_host = input[:director]
      components = input[:components]
      gateway = input[:gateway]

      director = connected_director(director_host, gateway)

      deployment =
        with_progress("Getting deployment info") do
          current_deployment(director)
        end

      locations =
        with_progress("Finding logs for #{c(deployment["name"], :name)}") do
          locs = stream_locations(director, deployment["name"], components)

          if locs.empty?
            fail "No locations found."
          else
            locs
          end
        end

      stream = stream_for(director, deployment["name"], gateway)

      stream.stream(locations) do |entry|
        line pretty_print_entry(entry)
      end
    end

    private

    def stream_for(director, deployment, gateway)
      user, host = gateway.split("@", 2)
      MultiLineStream.new(director, deployment, user, host)
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
        level_colored_message(entry),
        entry.data ? entry.data.inspect : ""
      ].join("  ")
    end

    def stream_locations(director, deployment, components)
      locations = Hash.new { |h, k| h[k] = [] }

      logs = LOGS.dup
      logs.select! { |l, _| components.include?(l) } unless components.empty?

      director.fetch_vm_state(deployment, :use_cache => false).each do |vm|
        name = vm["job_name"]
        index = vm["index"]
        next unless logs.key?(name)

        vm["ips"].each do |ip|
          logs[name].each do |file|
            locations[[name, index]] << StreamLocation.new(file, "#{name}/#{index}")
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

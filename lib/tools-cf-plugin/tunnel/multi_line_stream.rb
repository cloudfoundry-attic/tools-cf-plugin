require "base64"
require "json"
require "net/ssh/gateway"
require "thread"

module CFTools
  module Tunnel
    class MultiLineStream
      include Interact::Pretty

      def initialize(director, deployment, user, host)
        @director = director
        @deployment = deployment
        @gateway_user = user
        @gateway_host = host
      end

      def stream(locations)
        entries = entry_queue

        locations.each do |(name, index), locs|
          Thread.new do
            begin
              stream_location(name, index, locs, entries)
            rescue => e
              entries << LogEntry.new(
                "#{name}/#{index}",
                c("failed: #{e.class}: #{e}", :error),
                :stdout)

              retry
            end
          end
        end

        while entry = entries.pop
          yield entry
        end
      end

      private

      def gateway
        @gateway ||= Net::SSH::Gateway.new(@gateway_host, @gateway_user)
      end

      def entry_queue
        Queue.new
      end

      def public_key
        Net::SSH::Authentication::KeyManager.new(nil).each_identity do |i|
          return sane_public_key(i)
        end
      end

      def sane_public_key(pkey)
        "#{pkey.ssh_type} #{Base64.encode64(pkey.to_blob).split.join} #{pkey.comment}"
      end

      def generate_user
        "bosh_cf_watch_logs_#{rand(36**9).to_s(36)}"
      end

      def create_ssh_user(job, index, entries)
        user = generate_user

        entries << LogEntry.new(
          "#{job}/#{index}", c("creating user...", :warning), :stdout)

        status, task_id = @director.setup_ssh(
          @deployment, job, index, user,
          public_key, nil, :use_cache => false)

        raise "SSH setup failed." unless status == :done

        entries << LogEntry.new("#{job}/#{index}", c("created!", :good), :stdout)

        sessions = JSON.parse(@director.get_task_result_log(task_id))

        session = sessions.first

        raise "No session?" unless session

        [session["ip"], user]
      end

      def stream_location(job, index, locations, entries)
        ip, user = create_ssh_user(job, index, entries)

        entries << LogEntry.new(
          "#{job}/#{index}", c("connecting", :warning), :stdout)

        gateway.ssh(ip, user) do |ssh|
          entries << LogEntry.new(
            "#{job}/#{index}", c("connected!", :good), :stdout)

          locations.each do |loc|
            loc.stream_lines(ssh) do |entry|
              entries << entry
            end
          end
        end
      end
    end
  end
end

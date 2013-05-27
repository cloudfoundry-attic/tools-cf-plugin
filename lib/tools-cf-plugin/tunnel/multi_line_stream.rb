require "thread"
require "net/ssh/gateway"

module CFTools
  module Tunnel
    class MultiLineStream
      def initialize(user, host)
        @gateway_user = user
        @gateway_host = host
      end

      def stream(locations)
        entries = entry_queue

        locations.each do |ip, locs|
          Thread.new do
            stream_location(ip, locs, entries)
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

      def stream_location(ip, locations, entries)
        gateway.ssh(ip, @gateway_user) do |ssh|
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

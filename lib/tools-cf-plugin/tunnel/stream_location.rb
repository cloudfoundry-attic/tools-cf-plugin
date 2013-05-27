require "tools-cf-plugin/tunnel/log_entry"

module CFTools
  module Tunnel
    class StreamLocation
      attr_reader :path, :label

      def initialize(path, label)
        @path = path
        @label = label
      end

      def stream_lines(ssh)
        ssh.exec("tail -f /var/vcap/sys/log/#@path") do |ch, stream, chunk|
          if pending = ch[:pending]
            chunk = pending + chunk
            ch[:pending] = nil
          end

          chunk.each_line do |line|
            if line.end_with?("\n")
              yield log_entry(line, stream)
            else
              ch[:pending] = line
            end
          end
        end
      end

      private

      def log_entry(line, stream)
        LogEntry.new(@label, line, stream)
      end
    end
  end
end

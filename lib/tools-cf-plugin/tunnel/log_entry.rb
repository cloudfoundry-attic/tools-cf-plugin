require "json"
require "time"

module CFTools
  module Tunnel
    class LogEntry
      attr_reader :label, :line, :stream

      def initialize(label, line, stream)
        @label = label
        @line = line
        @stream = stream
        @fallback_timestamp = Time.now
      end

      def message
        json = JSON.parse(@line)
        json["message"]
      rescue JSON::ParserError
        @line
      end

      def log_level
        json = JSON.parse(@line)
        json["log_level"]
      rescue JSON::ParserError
      end

      def timestamp
        json = JSON.parse(@line)

        timestamp = json["timestamp"]
        case timestamp
        when String
          Time.parse(timestamp)
        when Numeric
          Time.at(timestamp)
        else
          @fallback_timestamp
        end
      rescue JSON::ParserError
        @fallback_timestamp
      end
    end
  end
end

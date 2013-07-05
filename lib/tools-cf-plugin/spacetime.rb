require "cf/cli"
require "time"

module CFTools
  class SpaceTime < CF::CLI
    def precondition; end

    def self.io_from_input
      proc do |name|
        if name == "-"
          $stdin
        else
          File.open(File.expand_path(name))
        end
      end
    end

    def self.pattern_from_input
      proc do |pat|
        Regexp.new(pat)
      end
    end

    desc "Space out line entries based on their timestamps."
    input :input, :argument => :required, :from_given => io_from_input,
          :desc => "Input source; '-' for stdin."
    input :pattern, :argument => :required, :from_given => pattern_from_input,
          :desc => "Regexp matching the timestamp in each log."
    input :scale, :type => :float, :default => 1.0,
          :desc => "Space scaling factor"
    def spacetime
      io = input[:input]
      pattern = input[:pattern]
      scale = input[:scale]

      prev_time = nil
      io.each do |entry|
        prev_time = space_line(
          entry, pattern, scale, prev_time)
      end
    end

    private

    def space_line(entry, pattern, scale, prev_time)
      matches = entry.match(pattern)
      return unless matches

      current_time = Time.parse(matches[1]) rescue return

      print_spacing(prev_time, current_time, scale)

      current_time
    ensure
      line entry.chomp
    end

    def print_spacing(prev_time, current_time, scale)
      return unless prev_time

      ((current_time - prev_time) * scale).round.times do
        line
      end
    end
  end
end

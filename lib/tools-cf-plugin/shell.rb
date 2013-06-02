require "cf/cli"
require "pry"
require "cli"

module CFTools
  class Shell < CF::CLI
    def precondition; end

    desc "Launch an IRB session with client APIs available."
    def shell
      binding.pry :quiet => true
    end
  end
end

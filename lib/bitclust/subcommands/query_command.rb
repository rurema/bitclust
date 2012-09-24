require 'pathname'
require 'erb'
require 'find'
require 'pp'
require 'optparse'
require 'yaml'

require 'bitclust'
require 'bitclust/subcommand'

module BitClust::Subcommands
  class QueryCommand < BitClust::Subcommand

    def initialize
      @parser = OptionParser.new {|opt|
        opt.banner = "Usage: #{File.basename($0, '.*')} query <ruby-script>"
        opt.on('--help', 'Prints this message and quit.') {
          puts opt.help
          exit 0
        }
      }
    end

    def parse(argv)
    end

    def exec(db, argv)
      argv.each do |query|
        #pp eval(query)   # FIXME: causes ArgumentError
        p eval(query)
      end
    end
  end
end

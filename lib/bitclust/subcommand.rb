require 'pathname'

require 'bitclust'
require 'erb'
require 'find'
require 'pp'
require 'optparse'
require 'yaml'

module BitClust

  class Subcommand
    def parse(argv)
      @parser.parse! argv
    end

    def help
      @parser.help
    end

    # TODO refactor
    def error(message)
      $stderr.puts "#{File.basename($0, '.*')}: error: #{message}"
      exit 1
    end
  end
end

module BitClust
  module Subcommands
  end
end


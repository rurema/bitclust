require 'pathname'

require 'bitclust'
require 'erb'
require 'find'
require 'pp'
require 'optparse'
require 'yaml'

module BitClust

  # Base class for bitclust subcommands.
  class Subcommand
    def initialize
      @parser = OptionParser.new
      @parser.on_tail("-h", "--help", "Print this message and quit."){
        $stderr.puts help
        exit 0
      }
    end

    def parse(argv)
      @parser.parse! argv
    end

    def help
      @parser.help
    end

    def exec(argv, options)
      prefix = options[:prefix]
      if options[:capi]
        @db = BitClust::FunctionDatabase.new(prefix)
      else
        @db = BitClust::MethodDatabase.new(prefix)
      end
    end

    # TODO refactor
    def error(message)
      $stderr.puts "#{File.basename($0, '.*')}: error: #{message}"
      exit 1
    end

    def option_error(message)
      $stderr.puts message
      $stderr.puts help
      exit 1
    end

    def srcdir_root
      Pathname.new(__FILE__).realpath.dirname.parent.parent
    end
  end
end

module BitClust
  module Subcommands
  end
end


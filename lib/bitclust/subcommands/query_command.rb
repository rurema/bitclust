require 'pathname'
require 'erb'
require 'find'
require 'pp'
require 'optparse'
require 'yaml'

require 'bitclust'
require 'bitclust/subcommand'

module BitClust
  module Subcommands
    class QueryCommand < Subcommand

      def initialize
        super
        @parser.banner = "Usage: #{File.basename($0, '.*')} query <ruby-script>"
      end

      def exec(argv, options)
        argv.each do |query|
          # pp eval(query)   # FIXME: causes ArgumentError
          p eval(query)
        end
      end
    end
  end
end

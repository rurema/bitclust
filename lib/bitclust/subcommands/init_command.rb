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
    class InitCommand < Subcommand
      def initialize
        super
        @parser.banner = "Usage: #{File.basename($0, '.*')} init [KEY=VALUE ...]"
      end

      STANDARD_PROPERTIES = %w( encoding version )

      def exec(argv, options)
        prefix = options[:prefix]
        db = MethodDatabase.new(prefix)
        db.init
        db.transaction {
          argv.each do |kv|
            k, v = kv.split('=', 2)
            db.propset k, v
          end
        }
        fail = false
        STANDARD_PROPERTIES.each do |key|
          unless db.propget(key)
            $stderr.puts "#{File.basename($0, '.*')}: warning: standard property `#{key}' not given"
            fail = true
          end
        end
        if fail
          $stderr.puts "---- Current Properties ----"
          db.properties.each do |key, value|
            $stderr.puts "#{key}=#{value}"
          end
        end
      end
    end
  end
end


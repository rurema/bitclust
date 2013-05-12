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
    class PropertyCommand < Subcommand
      def initialize
        super
        @mode = nil
        @parser.banner = "Usage: #{File.basename($0, '.*')} property [options]"
        @parser.on('--list', 'List all properties.') {
          @mode = :list
        }
        @parser.on('--get', 'Get property value.') {
          @mode = :get
        }
        @parser.on('--set', 'Set property value.') {
          @mode = :set
        }
      end

      def parse(argv)
        super
        unless @mode
          error "one of (--list|--get|--set) is required"
        end
        case @mode
        when :list
          unless argv.empty?
            error "--list requires no argument"
          end
        when :get
          ;
        when :set
          unless argv.size == 2
            error "--set requires just 2 arguments"
          end
        else
          raise "must not happen: #{@mode}"
        end
      end

      def exec(argv, options)
        prefix = options[:prefix]
        db = MethodDatabase.new(prefix)
        case @mode
        when :list
          db.properties.each do |key, val|
            puts "#{key}=#{val}"
          end
        when :get
          argv.each do |key|
            puts db.propget(key)
          end
        when :set
          key, val = *argv
          db.transaction {
            db.propset key, val
          }
        else
          raise "must not happen: #{@mode}"
        end
      end
    end
  end
end

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
    class ListCommand < Subcommand
      def initialize
        super
        @mode = nil
        @parser.banner = "Usage: #{File.basename($0, '.*')} list (--library|--class|--method|--function)"
        @parser.on('--library', 'List libraries.') {
          @mode = :library
        }
        @parser.on('--class', 'List classes.') {
          @mode = :class
        }
        @parser.on('--method', 'List methods.') {
          @mode = :method
        }
        @parser.on('--function', 'List functions (C API).') {
          @mode = :function
        }
      end

      def parse(argv)
        super
        unless @mode
          error 'one of (--library|--class|--method|--function) is required'
        end
      end

      def exec(argv, options)
        super
        case @mode
        when :library
          @db.libraries.map {|lib| lib.name }.sort.each do |name|
            puts name
          end
        when :class
          @db.classes.map {|c| c.name }.sort.each do |name|
            puts name
          end
        when :method
          @db.classes.sort_by {|c| c.name }.each do |c|
            c.entries.sort_by {|m| m.id }.each do |m|
              puts m.label
            end
          end
        when :function
          @db.functions.sort_by {|f| f.name }.each do |f|
            puts f.name
          end
        else
          raise "must not happen: @mode=#{@mode.inspect}"
        end
      end
    end
  end
end

require 'pathname'
require 'optparse'

require 'bitclust'
require 'bitclust/subcommand'

module BitClust
  module Subcommands
    class ExtractCommand < Subcommand

      def initialize
        super
        @parser.banner = "Usage: #{File.basename($0, '.*')} <file>..."
        @parser.on('-c', '--check-only', 'Check syntax and output status.') {
          @check_only = true
        }
      end

      def exec(argv, options)
        success = true
        argv.each do |path|
          begin
            lib = RRDParser.parse_stdlib_file(path)
            if @check_only
              $stderr.puts "#{path}: OK"
            else
              show_library lib
            end
          rescue WriterError => err
            raise if $DEBUG
            $stderr.puts "#{File.basename($0, '.*')}: FAIL: #{err.message}"
            success = false
          end
        end
        exit success
      end

      def show_library(lib)
        puts "= Library #{lib.name}"
        lib.classes.each do |c|
          puts "#{c.type} #{c.name}"
          c.each do |m|
            puts "\t* #{m.klass.name}#{m.typemark}#{m.names.join(',')}"
          end
        end
        unless lib.methods.empty?
          puts "Additional Methods:"
          lib.methods.each do |m|
            puts "\t* #{m.klass.name}#{m.typemark}#{m.names.join(',')}"
          end
        end
      end
    end
  end
end

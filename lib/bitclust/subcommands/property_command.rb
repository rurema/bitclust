require 'pathname'
require 'erb'
require 'find'
require 'pp'
require 'optparse'
require 'yaml'

require 'bitclust'
require 'bitclust/subcommand'

module BitClust::Subcommands
  class PropertyCommand < BitClust::Subcommand
    def initialize
      @mode = nil
      @parser = OptionParser.new {|opt|
        opt.banner = "Usage: #{File.basename($0, '.*')} property [options]"
        opt.on('--list', 'List all properties.') {
          @mode = :list
        }
        opt.on('--get', 'Get property value.') {
          @mode = :get
        }
        opt.on('--set', 'Set property value.') {
          @mode = :set
        }
        opt.on('--help', 'Prints this message and quit.') {
          puts opt.help
          exit 0
        }
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

    def exec(db, argv)
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

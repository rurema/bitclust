require 'pathname'
require 'erb'
require 'find'
require 'pp'
require 'optparse'
require 'yaml'

require 'bitclust'
require 'bitclust/subcommand'

module BitClust::Subcommands
  class InitCommand < BitClust::Subcommand
    def initialize
      @parser = OptionParser.new {|opt|
        opt.banner = "Usage: #{File.basename($0, '.*')} init [KEY=VALUE ...]"
        opt.on('--help', 'Prints this message and quit.') {
          puts opt.help
          exit 0
        }
      }
    end

    STANDARD_PROPERTIES = %w( encoding version )

    def exec(db, argv)
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


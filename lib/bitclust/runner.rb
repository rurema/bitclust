require 'pathname'
require 'optparse'

unless Object.const_defined?(:Encoding)
  $KCODE = 'UTF-8'
end

def srcdir_root
  Pathname.new(__FILE__).realpath.dirname.parent.cleanpath
end

$LOAD_PATH.unshift((srcdir_root() + 'lib').to_s)

require 'bitclust'
require 'bitclust/subcommand'

module BitClust
  class Runner
    def initialize
    end

    def run(argv)
      Signal.trap(:PIPE, 'IGNORE') rescue nil   # Win32 does not have SIGPIPE
      Signal.trap(:INT) { exit 3 }
      prepare
      _run(argv)
    rescue Errno::EPIPE
      exit 0
    end

    def prepare
      @prefix = nil
      @version = nil
      @capi = false
      @parser = OptionParser.new
      @parser.banner = <<-EndBanner
Usage: #{File.basename($0, '.*')} [global options] <subcommand> [options] [args]

Subcommands:
    init        Initialize database.
    list        List libraries/classes/methods in database.
    lookup      Lookup a library/class/method from database.
    search      Search classes/methods from database.
    query       Dispatch arbitrary query.
    update      Update database.
    property    Handle database properties.
    setup       Initialize and update database with default options.

Global Options:
  EndBanner
      @parser.on('-d', '--database=PATH', 'Database prefix.') {|path|
        @prefix = path
      }
      @parser.on('-t', '--targer=VERSION', 'Specify Ruby version.') {|v|
        @version = v
      }
      @parser.on('--capi', 'Process C API database.') {
        @capi = true
      }
      @parser.on('--version', 'Print version and quit.') {
        puts BitClust::VERSION
        exit 0
      }
      @parser.on('--help', 'Prints this message and quit.') {
        puts @parser.help
        exit 0
      }
      @subcommands = {
        'init'     => BitClust::InitCommand.new,
        'list'     => BitClust::ListCommand.new,
        'lookup'   => BitClust::LookupCommand.new,
        'search'   => BitClust::Searcher.new,
        'query'    => BitClust::QueryCommand.new,
        'update'   => BitClust::UpdateCommand.new,
        'property' => BitClust::PropertyCommand.new,
        'setup'    => BitClust::SetupCommand.new,
        'server'   => BitClust::ServerCommand.new,
      }
    end

    def _run(argv)
      begin
        @parser.order!(argv)
        if argv.empty?
          $stderr.puts 'no sub-command given'
          $stderr.puts @parser.help
          exit 1
        end
        name = argv.shift
        cmd = @subcommands[name] or error "no such sub-command: #{name}"
      rescue OptionParser::ParseError => err
        $stderr.puts err.message
        $stderr.puts @parser.help
        exit 1
      end
      begin
        cmd.parse(argv)
      rescue OptionParser::ParseError => err
        $stderr.puts err.message
        $stderr.puts cmd.help
        exit 1
      end
      case name
      when "setup", "server"
        db = nil
      else
        config = load_config()
        if config
          @version ||= config[:default_version]
          @prefix ||= "#{config[:database_prefix]}-#{@version}"
        end
        unless @prefix
          $stderr.puts "no database given. Use --database option"
          exit 1
        end
        if @capi
          db = BitClust::FunctionDatabase.new(@prefix)
        else
          db = BitClust::MethodDatabase.new(@prefix)
        end
      end
      cmd.exec(db, argv)
    rescue BitClust::WriterError => err
      raise if $DEBUG
      error err.message
    end

    def load_config
      home_directory = Pathname(ENV['HOME'])
      config_path = home_directory + ".bitclust/config"
      if config_path.exist?
        YAML.load_file(config_path)
      else
        nil
      end
    end

    def error(message)
      $stderr.puts "#{File.basename($0, '.*')}: error: #{message}"
      exit 1
    end
  end
end

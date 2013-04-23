require 'pathname'
require 'optparse'

unless Object.const_defined?(:Encoding)
  $KCODE = 'UTF-8'
end

def libdir
  Pathname.new(__FILE__).realpath.dirname.parent.cleanpath
end

$LOAD_PATH.unshift(libdir.to_s)

require 'bitclust'
require 'bitclust/subcommand'

subcommands_dir = libdir + "bitclust/subcommands"
Dir.glob(File.join(subcommands_dir.to_s, "*.rb")) do |entry|
  require "bitclust/subcommands/#{File.basename(entry, ".rb")}"
end

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
    statichtml  Generate static HTML files.
    htmlfile    Generate a static HTML file for test.
    chm         Generate static HMLT files for CHM.

Global Options:
  EndBanner
      @parser.on('-d', '--database=PATH', 'Database prefix.') {|path|
        @prefix = path
      }
      @parser.on('-t', '--target=VERSION', 'Specify Ruby version.') {|v|
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
        'init'        => BitClust::Subcommands::InitCommand.new,
        'list'        => BitClust::Subcommands::ListCommand.new,
        'lookup'      => BitClust::Subcommands::LookupCommand.new,
        'search'      => BitClust::Searcher.new,
        'query'       => BitClust::Subcommands::QueryCommand.new,
        'update'      => BitClust::Subcommands::UpdateCommand.new,
        'property'    => BitClust::Subcommands::PropertyCommand.new,
        'setup'       => BitClust::Subcommands::SetupCommand.new,
        'server'      => BitClust::Subcommands::ServerCommand.new,
        'statichtml'  => BitClust::Subcommands::StatichtmlCommand.new,
        'htmlfile'    => BitClust::Subcommands::HtmlfileCommand.new,
        'chm'         => BitClust::Subcommands::ChmCommand.new,
        'ancestors'   => BitClust::Subcommands::AncestorsCommand.new,
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
      config = load_config()
      if config
        @version ||= config[:default_version]
        @prefix ||= "#{config[:database_prefix]}-#{@version}"
      end
      unless @prefix
        $stderr.puts "no database given. Use --database option"
        exit 1
      end
      options = {
        :prefix => @prefix,
        :capi   => @capi
      }
      cmd.exec(argv, options)
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

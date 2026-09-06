# frozen_string_literal: true
require 'pathname'
require 'optparse'

unless Object.const_defined?(:Encoding)
  $KCODE = 'UTF-8' # steep:ignore
end

def libdir
  Pathname.new(__FILE__).realpath.dirname.parent.cleanpath
end

$LOAD_PATH.unshift(libdir.to_s)

require 'bitclust'
require 'bitclust/subcommand'
require 'bitclust/user_dirs'

subcommands_dir = libdir + "bitclust/subcommands"
Dir.glob(File.join(subcommands_dir.to_s, "*.rb")) do |entry|
  require "bitclust/subcommands/#{File.basename(entry, ".rb")}"
end

module BitClust
  # Body of bin/bitclust.
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

Subcommands(for users):
    init        Initialize database.
    update      Update database.
    setup       Initialize and update database with default options.
    list        List libraries/classes/methods in database.
    lookup      Lookup a library/class/method from database.
    search      Search classes/methods from database.
    server      Run HTTP server to browse the reference manual.

Subcommands(for developers):
    ancestors   Compare class/module's ancestors between Ruby and DB.
    htmlfile    Generate a static HTML file for test.
    query       Dispatch arbitrary query.
    property    Handle database properties.
    preproc     Preprocess source file.
    extract     Extract method entries from source file.
    classes     Display defined classes for all ruby.
    methods     Display defined methods for all ruby.
    methodsince Fill per-name since/until from a version ladder of DBs.
    rbssig      Fill RBS type signatures into a 4.0+ DB from .rbs files.
    checklink   Report broken [[c:]]/[[m:]]/[[lib:]]/[[d:]]/[[f:]] links.

Subcommands(for packagers):
    statichtml  Generate static HTML files.
    searchpage  Generate a static cross-version search page.
    epub        Generate EPUB file.
    chm         Generate static HTML files for CHM.

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
        'searchpage'  => BitClust::Subcommands::SearchpageCommand.new,
        'htmlfile'    => BitClust::Subcommands::HtmlfileCommand.new,
        'chm'         => BitClust::Subcommands::ChmCommand.new,
        'epub'        => BitClust::Subcommands::EPUBCommand.new,
        'ancestors'   => BitClust::Subcommands::AncestorsCommand.new,
        'preproc'     => BitClust::Subcommands::PreprocCommand.new,
        'extract'     => BitClust::Subcommands::ExtractCommand.new,
        'classes'     => BitClust::Subcommands::ClassesCommand.new,
        'methods'     => BitClust::Subcommands::MethodsCommand.new,
        'methodsince' => BitClust::Subcommands::MethodsinceCommand.new,
        'rbssig'      => BitClust::Subcommands::RbssigCommand.new,
        'checklink'   => BitClust::Subcommands::ChecklinkCommand.new,
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
      # DB 必須のサブコマンドで --database も設定ファイル(UserDirs)も
      # 無ければ案内付きで中断する。needs_database? が false のサブコマンドと、
      # 自前で DB を探す search (Searcher) は対象外
      needs_database = cmd.respond_to?(:needs_database?) && cmd.needs_database?
      if needs_database && !@prefix
        error "no database given. Use --database (-d) option or run `bitclust setup` (config: #{UserDirs.config_candidates.join(' or ')})"
      end
      # @type var options: Subcommand::options
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
      UserDirs.load_config
    end

    def error(message)
      $stderr.puts "#{File.basename($0, '.*')}: error: #{message}"
      exit 1
    end
  end
end

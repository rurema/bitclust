require 'pathname'
require 'erb'
require 'find'
require 'pp'
require 'optparse'
require 'yaml'
require 'webrick'
require 'uri'

require 'bitclust'
require 'bitclust/subcommand'

module BitClust
  module Subcommands
    class ServerCommand < Subcommand
      def initialize
        super
        require 'webrick'
        require 'uri'

        @params = {
          :BindAddress => "0.0.0.0",
          :Port => 10080
        }
        @baseurl = nil
        @dbpath = nil
        @srcdir = @datadir = @themedir = @theme = @templatedir = nil
        @encoding = 'utf-8'   # encoding of view
        if Object.const_defined?(:Encoding)
          Encoding.default_external = @encoding
        end

        @debugp = false
        @autop = false
        @browser = nil
        @pid_file = nil
        @capi = false

        @parser.banner = "#{$0} [--bind-address=ADDR] [--port=NUM] --baseurl=URL --database=PATH [--srcdir=PATH] [--datadir=PATH] [--themedir=PATH] [--debug] [--auto] [--browser=BROWSER] [--pid-file=PATH] [--capi]"
        @parser.on('--bind-address=ADDR', 'Bind address') {|addr|
          @params[:BindAddress] = addr
        }
        @parser.on('--port=NUM', 'Listening port number') {|num|
          @params[:Port] = num.to_i
        }
        @parser.on('--baseurl=URL', 'The base URL to host.') {|url|
          @baseurl = url
        }
        @parser.on('--database=PATH', 'MethodDatabase root directory.') {|path|
          @dbpath = path
        }
        @parser.on('--srcdir=PATH', 'BitClust source directory.') {|path|
          set_srcdir(path)
        }
        @parser.on('--datadir=PATH', 'BitClust data directory.') {|path|
          @datadir = path
        }
        @parser.on('--templatedir=PATH', 'Template directory.') {|path|
          @templatedir = path
        }
        @parser.on('--themedir=PATH', 'BitClust theme directory.') {|path|
          @themedir = path
        }
        @parser.on('--theme=THEME', 'BitClust theme.') {|th|
          @theme = th
        }
        @parser.on('--[no-]debug', 'Debug mode.') {|flag|
          @debugp = flag
        }
        @parser.on('--[no-]auto', 'Auto mode.') {|flag|
          @autop = flag
        }
        @parser.on('--browser=BROWSER', 'Open with the browser.') {|path|
          @browser = path
        }
        @parser.on('--pid-file=PATH', 'Write pid of the daemon to the specified file.') {|path|
          @pid_file = path
        }
        @parser.on('--capi', 'see also FunctionDatabase.') {|path|
          @capi = true
        }
      end

      def parse(argv)
        super
        load_config_file
        set_srcdir(srcdir_root) unless @srcdir

        unless @baseurl
          $stderr.puts "missing base URL.  Use --baseurl or check ~/.bitclust/config"
          exit 1
        end
        unless @dbpath || @autop
          $stderr.puts "missing database path.  Use --database"
          exit 1
        end
        unless @datadir
          $stderr.puts "missing datadir.  Use --datadir"
          exit 1
        end
        unless @themedir
          $stderr.puts "missing themedir.  Use --themedir"
          exit 1
        end
        if @pid_file
          if File.exist?(@pid_file)
            $stderr.puts "There is still #{@pid_file}.  Is another process running?"
            exit 1
          end
          @pid_file = File.expand_path(@pid_file)
        end
      end

      def exec(argv, options)
        require 'bitclust/app'
        if @debugp
          @params[:Logger] = WEBrick::Log.new($stderr, WEBrick::Log::DEBUG)
          @params[:AccessLog] = [
                                 [ $stderr, WEBrick::AccessLog::COMMON_LOG_FORMAT  ],
                                 [ $stderr, WEBrick::AccessLog::REFERER_LOG_FORMAT ],
                                 [ $stderr, WEBrick::AccessLog::AGENT_LOG_FORMAT   ],
                                ]
        else
          @params[:Logger] = WEBrick::Log.new($stderr, WEBrick::Log::INFO)
          @params[:AccessLog] = []
        end
        basepath = URI.parse(@baseurl).path
        server = WEBrick::HTTPServer.new(@params)

        if @autop
          app = App.new(
                        :dbpath => Dir.glob("#{@database_prefix}-*"),
                        :baseurl => @baseurl,
                        :datadir => @datadir,
                        :templatedir => @templatedir,
                        :theme => @theme,
                        :encoding => @encoding,
                        :capi => @capi
                        )
          app.interfaces.each do |version, interface|
            server.mount(File.join(basepath, version), interface)
          end
          server.mount(File.join(basepath, '/'), app)
        else
          viewpath = File.join(basepath, 'view')
          app = App.new(
                        :viewpath => viewpath,
                        :dbpath => @dbpath,
                        :baseurl => @baseurl,
                        :datadir => @datadir,
                        :templatedir => @templatedir,
                        :theme => @theme,
                        :encoding => @encoding,
                        :capi => @capi
                        )
          app.interfaces.each do |viewpath, interface|
            server.mount viewpath, interface
          end
          # Redirect from '/' to "#{viewpath}/"
          server.mount('/', app)
        end

        server.mount File.join(basepath, 'theme/'), WEBrick::HTTPServlet::FileHandler, @themedir

        if @debugp
          trap(:INT) { server.shutdown }
        else
          WEBrick::Daemon.start do
            trap(:TERM) {
              server.shutdown
              begin
                File.unlink @pid_file if @pid_file
              rescue Errno::ENOENT
              end
            }
            File.open(@pid_file, 'w') {|f| f.write Process.pid } if @pid_file
          end
        end
        exit if $".include?("exerb/mkexy.rb")
        if @autop && !@browser
          case RUBY_PLATFORM
          when /mswin/
            @browser = "start"
          end
        end
        system("#{@browser} http://localhost:#{@params[:Port]}/") if @browser
        server.start
      end

      private

      def srcdir_root
        Pathname.new(__FILE__).realpath.dirname.parent.parent.parent.cleanpath
      end

      def set_srcdir(dir)
        @srcdir ||= dir
        @datadir ||= "#{@srcdir}/data/bitclust"
        @themedir ||= "#{@srcdir}/theme"
      end

      def load_config_file
        home_directory = Pathname(ENV['HOME'])
        config_path = home_directory + ".bitclust/config"
        if config_path.exist?
          config = YAML.load_file(config_path)
          @baseurl  ||= config[:baseurl]
          @dbpath   ||= "#{config[:database_prefix]}-#{config[:default_version]}"
          @port     ||= config[:port]
          @pid_file ||= config[:pid_file]
          @database_prefix ||= config[:database_prefix]
        end
      end
    end
  end
end

require 'pathname'

require 'bitclust'
require 'erb'
require 'find'
require 'pp'
require 'optparse'
require 'yaml'

module BitClust

  class Subcommand
    def parse(argv)
      @parser.parse! argv
    end

    def help
      @parser.help
    end
  end


  class InitCommand < Subcommand

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


  class UpdateCommand < Subcommand

    def initialize
      @root = nil
      @library = nil
      @parser = OptionParser.new {|opt|
        opt.banner = "Usage: #{File.basename($0, '.*')} update [<file>...]"
        opt.on('--stdlibtree=ROOT', 'Process stdlib source directory tree.') {|path|
          @root = path
        }
        opt.on('--library-name=NAME', 'Use NAME for library name in file mode.') {|name|
          @library = name
        }
        opt.on('--help', 'Prints this message and quit.') {
          puts opt.help
          exit 0
        }
      }
    end

    def parse(argv)
      super
      if not @root and argv.empty?
        error "no input file given"
      end
    end

    def exec(db, argv)
      db.transaction {
        if @root
          db.update_by_stdlibtree @root
        end
        argv.each do |path|
          db.update_by_file path, @library || guess_library_name(path)
        end
      }
    end

    private

    def guess_library_name(path)
      if %r<(\A|/)src/> =~ path
        path.sub(%r<.*(\A|/)src/>, '').sub(/\.rd\z/, '')
      else
        path
      end
    end

    def get_c_filename(path)
      File.basename(path, '.rd')
    end

  end


  class ListCommand < Subcommand

    def initialize
      @mode = nil
      @parser = OptionParser.new {|opt|
        opt.banner = "Usage: #{File.basename($0, '.*')} list (--library|--class|--method|--function)"
        opt.on('--library', 'List libraries.') {
          @mode = :library
        }
        opt.on('--class', 'List classes.') {
          @mode = :class
        }
        opt.on('--method', 'List methods.') {
          @mode = :method
        }
        opt.on('--function', 'List functions.') {
          @mode = :function
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
        error 'one of (--library|--class|--method|--function) is required'
      end
    end

    def exec(db, argv)
      case @mode
      when :library
        db.libraries.map {|lib| lib.name }.sort.each do |name|
          puts name
        end
      when :class
        db.classes.map {|c| c.name }.sort.each do |name|
          puts name
        end
      when :method
        db.classes.sort_by {|c| c.name }.each do |c|
          c.entries.sort_by {|m| m.id }.each do |m|
            puts m.label
          end
        end
      when :function
        db.functions.sort_by {|f| f.name }.each do |f|
          puts f.name
        end
      else
        raise "must not happen: @mode=#{@mode.inspect}"
      end
    end

  end


  class LookupCommand < Subcommand

    def initialize
      @format = :text
      @type = nil
      @key = nil
      @parser = OptionParser.new {|opt|
        opt.banner = "Usage: #{File.basename($0, '.*')} lookup (--library|--class|--method|--function) [--html] <key>"
        opt.on('--library=NAME', 'Lookup library.') {|name|
          @type = :library
          @key = name
        }
        opt.on('--class=NAME', 'Lookup class.') {|name|
          @type = :class
          @key = name
        }
        opt.on('--method=NAME', 'Lookup method.') {|name|
          @type = :method
          @key = name
        }
        opt.on('--function=NAME', 'Lookup function.') {|name|
          @type = :function
          @key = name
        }
        opt.on('--html', 'Show result in HTML.') {
          @format = :html
        }
        opt.on('--help', 'Prints this message and quit.') {
          puts opt.help
          exit 0
        }
      }
    end

    def parse(argv)
      super
      unless @type
        error "one of --library/--class/--method/--function is required"
      end
      unless argv.empty?
        error "too many arguments"
      end
    end

    def exec(db, argv)
      entry = fetch_entry(db, @type, @key)
      puts fill_template(get_template(@type, @format), entry)
    end

    def fetch_entry(db, type, key)
      case type
      when :library
        db.fetch_library(key)
      when :class
        db.fetch_class(key)
      when :method
        db.fetch_method(BitClust::MethodSpec.parse(key))
      when :function
        db.fetch_function(key)
      else
        raise "must not happen: #{type.inspect}"
      end
    end

    def fill_template(template, entry)
      ERB.new(template).result(binding())
    end

    def get_template(type, format)
      template = TEMPLATE[type][format]
      BitClust::TextUtils.unindent_block(template.lines).join('')
    end

    TEMPLATE = {
      :library => {
        :text => <<-End,
           type: library
           name: <%= entry.name %>
           classes: <%= entry.classes.map {|c| c.name }.sort.join(', ') %>
           methods: <%= entry.methods.map {|m| m.name }.sort.join(', ') %>

           <%= entry.source %>
           End
        :html => <<-End
           <dl>
           <dt>type</dt><dd>library</dd>
           <dt>name</dt><dd><%= entry.name %></dd>
           <dt>classes</dt><dd><%= entry.classes.map {|c| c.name }.sort.join(', ') %></dd>
           <dt>methods</dt><dd><%= entry.methods.map {|m| m.name }.sort.join(', ') %></dd>
           </dl>
           <%= compile_rd(entry.source) %>
           End
      },
      :class   => {
        :text => <<-End,
           type: class
           name: <%= entry.name %>
           library: <%= entry.library.name %>
           singleton_methods: <%= entry.singleton_methods.map {|m| m.name }.sort.join(', ') %>
           instance_methods: <%= entry.instance_methods.map {|m| m.name }.sort.join(', ') %>
           constants: <%= entry.constants.map {|m| m.name }.sort.join(', ') %>
           special_variables: <%= entry.special_variables.map {|m| '$' + m.name }.sort.join(', ') %>

           <%= entry.source %>
           End
        :html => <<-End
           <dl>
           <dt>type</dt><dd>class</dd>
           <dt>name</dt><dd><%= entry.name %></dd>
           <dt>library</dt><dd><%= entry.library.name %></dd>
           <dt>singleton_methods</dt><dd><%= entry.singleton_methods.map {|m| m.name }.sort.join(', ') %></dd>
           <dt>instance_methods</dt><dd><%= entry.instance_methods.map {|m| m.name }.sort.join(', ') %></dd>
           </dl>
           <%= compile_rd(entry.source) %>
           End
      },
      :method  => {
        :text => <<-End,
           type: <%= entry.type %>
           name: <%= entry.name %>
           names: <%= entry.names.sort.join(', ') %>
           visibility: <%= entry.visibility %>
           kind: <%= entry.kind %>
           library: <%= entry.library.name %>

           <%= entry.source %>
           End
        :html => <<-End
           <dl>
           <dt>type</dt><dd><%= entry.type %></dd>
           <dt>name</dt><dd><%= entry.name %></dd>
           <dt>names</dt><dd><%= entry.names.sort.join(', ') %></dd>
           <dt>visibility</dt><dd><%= entry.visibility %></dd>
           <dt>kind</dt><dd><%= entry.kind %></dd>
           <dt>library</dt><dd><%= entry.library.name %></dd>
           </dl>
           <%= compile_rd(entry.source) %>
           End
      },
      :function => {
        :text => <<-End,
           kind: <%= entry.kind %>
           header: <%= entry.header %>
           filename: <%= entry.filename %>

           <%= entry.source %>
           End
        :html => <<-End
           <dl>
           <dt>kind</dt><dd><%= entry.kind %></dd>
           <dt>header</dt><dd><%= entry.header %></dd>
           <dt>filename</dt><dd><%= entry.filename %></dd>
           </dl>
           <%= compile_rd(entry.source) %>
           End
      }
    }

    def compile_rd(src)
      umap = BitClust::URLMapper.new(:base_url => 'http://example.com',
                                     :cgi_url  => 'http://example.com/view')
      compiler = BitClust::RDCompiler.new(umap, 2)
      compiler.compile(src)
    end

  end


  class QueryCommand < Subcommand

    def initialize
      @parser = OptionParser.new {|opt|
        opt.banner = "Usage: #{File.basename($0, '.*')} query <ruby-script>"
        opt.on('--help', 'Prints this message and quit.') {
          puts opt.help
          exit 0
        }
      }
    end

    def parse(argv)
    end

    def exec(db, argv)
      argv.each do |query|
        #pp eval(query)   # FIXME: causes ArgumentError
        p eval(query)
      end
    end
  end


  class PropertyCommand < Subcommand

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

  class SetupCommand < Subcommand

    REPOSITORY_PATH = "http://jp.rubyist.net/svn/rurema/doctree/trunk"

    def initialize
      @prepare = nil
      @cleanup = nil
      @versions = ["1.8.7", "1.9.2", "1.9.3"]
      @parser = OptionParser.new {|opt|
        opt.banner = "Usage: #{File.basename($0, '.*')} setup [options]"
        opt.on('--prepare', 'Prepare config file and checkout repository. Do not create database.') {
          @prepare = true
        }
        opt.on('--cleanup', 'Cleanup datebase before create database.') {
          @cleanup = true
        }
        opt.on('--versions=V1,V2,...', "Specify versions. [#{@versions.join(',')}]") {|versions|
          @versions = versions.split(",")
        }
        opt.on('--help', 'Prints this message and quit.') {
          puts opt.help
          exit 0
        }
      }
    end

    def exec(db, argv)
      prepare
      return if @prepare
      @config[:versions].each do |version|
        puts "Generating database for Ruby#{version}..."
        prefix = "#{@config[:database_prefix]}-#{version}"
        FileUtils.rm_ rf(prefix) if @cleanup
        init_argv = ["version=#{version}", "encoding=#{@config[:encoding]}"]
        db = BitClust::MethodDatabase.new(prefix)
        InitCommand.new.exec(db, init_argv)
        update_method_database(prefix, ["--stdlibtree=#{@config[:stdlibtree]}"])
        argv = Pathname(@config[:capi_src]).children.select(&:file?).map{|v| v.realpath.to_s }
        update_function_database(prefix, argv)
      end
    end

    private

    def prepare
      home_directory = Pathname(ENV["HOME"])
      config_dir = home_directory + ".bitclust"
      config_dir.mkpath
      config_path = config_dir + "config"
      rubydoc_dir = config_dir + "rubydoc"
      @config = {
        :database_prefix => (config_dir + "db").to_s,
        :encoding => "euc-jp",
        :versions => @versions,
        :defualt_version => @versions.max,
        :stdlibtree => (rubydoc_dir + "refm/api/src").to_s,
        :capi_src => (rubydoc_dir + "refm/capi/src/").to_s,
        :beseurl => "http://localhost:10080",
        :port => "10080",
        :pid_file => "/tmp/bitclust.pid",
      }
      if config_path.exist?
        @config = YAML.load_file(config_path)
        unless @config[:versions] == @versions
          @config[:versions] = @versions
          @config[:default_version] = @versions.max
        end
        generate_config(config_path, @config)
      else
        generate_config(config_path, @config)
      end
      checkout(rubydoc_dir)
    end

    def generate_config(path, config)
      path.open("w+", 0644) do |file|
        file.puts config.to_yaml
      end
    end

    def checkout(rubydoc_dir)
      system("svn", "co", REPOSITORY_PATH, rubydoc_dir.to_s)
    end

    def update_method_database(prefix, argv)
      db = BitClust::MethodDatabase.new(prefix)
      cmd = UpdateCommand.new
      cmd.parse(argv)
      cmd.exec(db, argv)
    end

    def update_function_database(prefix, argv)
      db = BitClust::FunctionDatabase.new(prefix)
      cmd = UpdateCommand.new
      cmd.parse(argv)
      cmd.exec(db, argv)
    end

  end

  class ServerCommand < Subcommand

    def initialize
      require 'webrick'
      require 'uri'

      @params = {
        :Port => 10080
      }
      @baseurl = nil
      @dbpath = nil
      @srcdir = @datadir = @themedir = @theme = @templatedir = nil
      @encoding = 'euc-jp'   # encoding of view
      if Object.const_defined?(:Encoding)
        Encoding.default_external = @encoding
      end

      @debugp = false
      @autop = false
      @browser = nil
      @pid_file = nil
      @capi = false

      @parser = OptionParser.new
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
        @set_srcdir.call path
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
      @parser.on('--help', 'Prints this message and quit.') {
        puts @parser.help
        exit 0
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
        $stderr.puts "missing base URL.  Use --baseurl"
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
          $stderr.puts "There is still #{pid_file}.  Is another process running?"
          exit 1
        end
        @pid_file = File.expand_path(@pid_file)
      end
    end

    def exec(db, argv)
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
        app = BitClust::App.new(
          :dbpath => Dir.glob("db-*"),
          :baseurl => @baseurl,
          :datadir => @datadir,
          :templatedir => @templatedir,
          :theme => @theme,
          :encoding => @encoding,
          :capi => @capi
        )
        app.interfaces.each do |version, interface|
          server.mount File.join(basepath, version), interface
        end
        server.mount(File.join(basepath, '/'), app)
      else
        viewpath = File.join(basepath, 'view')
        app = BitClust::App.new(
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
      system("#{browser} http://localhost:#{params[:Port]}/") if @browser
      server.start
    end

    private

    def srcdir_root
      Pathname.new(__FILE__).realpath.dirname.parent.parent.cleanpath
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
      end
    end

  end

end

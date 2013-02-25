require 'pathname'
require 'erb'
require 'find'
require 'pp'
require 'optparse'
require 'yaml'

require 'bitclust'
require 'bitclust/subcommand'

module BitClust::Subcommands
  class SetupCommand < BitClust::Subcommand

    REPOSITORY_PATH = "http://jp.rubyist.net/svn/rurema/doctree/trunk"

    def initialize
      @prepare = nil
      @cleanup = nil
      @versions = ["1.8.7", "1.9.3", "2.0.0"]
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
        FileUtils.rm_rf(prefix) if @cleanup
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
        :encoding => "utf-8",
        :versions => @versions,
        :default_version => @versions.max,
        :stdlibtree => (rubydoc_dir + "refm/api/src").to_s,
        :capi_src => (rubydoc_dir + "refm/capi/src/").to_s,
        :baseurl => "http://localhost:10080",
        :port => "10080",
        :pid_file => "/tmp/bitclust.pid",
      }
      if config_path.exist?
        @config = YAML.load_file(config_path)
        unless @config[:versions].sort == @versions.sort
          print("overwrite config file? > [y/N]")
          if /\Ay\z/i =~ $stdin.gets.chomp
            @config[:versions] = @versions
            @config[:default_version] = @versions.max
            generate_config(config_path, @config)
          end
        end
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
      case RUBY_PLATFORM
      when /mswin(?!ce)|mingw|cygwin|bccwin/
        cmd = "svn help > NUL 2> NUL"
      else
        cmd = "svn help > /dev/null 2> /dev/null"
      end
      unless system(cmd)
        warn "svn command is not found. Please install Subversion."
        exit 1
      end
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
end

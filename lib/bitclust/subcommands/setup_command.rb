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
    class SetupCommand < Subcommand

      REPOSITORY_PATH = "http://jp.rubyist.net/svn/rurema/doctree/trunk"

      def initialize
        super
        @prepare = nil
        @cleanup = nil
        @versions = ["1.8.7", "1.9.3", "2.0.0"]
        @parser.banner = "Usage: #{File.basename($0, '.*')} setup [options]"
        @parser.on('--prepare', 'Prepare config file and checkout repository. Do not create database.') {
          @prepare = true
        }
        @parser.on('--cleanup', 'Cleanup datebase before create database.') {
          @cleanup = true
        }
        @parser.on('--versions=V1,V2,...', "Specify versions. [#{@versions.join(',')}]") {|versions|
          @versions = versions.split(",")
        }
      end

      def exec(argv, options)
        prepare
        return if @prepare
        @config[:versions].each do |version|
          puts "Generating database for Ruby#{version}..."
          prefix = "#{@config[:database_prefix]}-#{version}"
          FileUtils.rm_rf(prefix) if @cleanup
          init_argv = ["version=#{version}", "encoding=#{@config[:encoding]}"]
          init_options = { :prefix => prefix }
          InitCommand.new.exec(init_argv, init_options)
          update_method_database(prefix, ["--stdlibtree=#{@config[:stdlibtree]}"])
          update_argv = Pathname(@config[:capi_src]).children.select(&:file?).map{|v| v.realpath.to_s }
          update_function_database(prefix, update_argv)
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
          :encoding        => "utf-8",
          :versions        => @versions,
          :default_version => @versions.max,
          :stdlibtree      => (rubydoc_dir + "refm/api/src").to_s,
          :capi_src        => (rubydoc_dir + "refm/capi/src/").to_s,
          :baseurl         => "http://localhost:10080",
          :port            => "10080",
          :pid_file        => "/tmp/bitclust.pid",
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
        unless system("svn", "co", REPOSITORY_PATH, rubydoc_dir.to_s)
          warn "svn command failed. Please install Subversion or check your PATH."
          exit 1
        end
      end

      def update_method_database(prefix, argv)
        options = {
          :prefix => prefix,
          :capi => false,
        }
        cmd = UpdateCommand.new
        cmd.parse(argv)
        cmd.exec(argv, options)
      end

      def update_function_database(prefix, argv)
        options = {
          :prefix => prefix,
          :capi => true,
        }
        cmd = UpdateCommand.new
        cmd.parse(argv)
        cmd.exec(argv, options)
      end
    end
  end
end

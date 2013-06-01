require 'bitclust'
require 'bitclust/runner'

class TestRunner < Test::Unit::TestCase
  def setup
    @runner = BitClust::Runner.new
    home_directory = Pathname(ENV['HOME'])
    @config_path = home_directory + ".bitclust/config"
    @config = {
      :default_version => "1.9.3",
      :database_prefix => "/home/user/.bitclust/db"
    }
    @prefix = "/home/user/.bitclust/db-1.9.3"
    @db = Object.new
  end

  def test_run_setup
    command = mock(Object.new)
    mock(::BitClust::Subcommands::SetupCommand).new.returns(command)
    mock(@runner).load_config.returns(@config)
    command.parse([])
    command.exec([], {:prefix => @prefix, :capi => false}).returns(nil)
    @runner.run(["setup"])
  end

  def test_run_server
    command = mock(Object.new)
    mock(::BitClust::Subcommands::ServerCommand).new.returns(command)
    mock(@runner).load_config.returns(@config)
    command.parse([])
    command.exec([], {:prefix => @prefix, :capi => false}).returns(nil)
    @runner.run(["server"])
  end

  def test_run_init
    command = mock(Object.new)
    mock(::BitClust::Subcommands::InitCommand).new.returns(command)
    mock(@runner).load_config.returns(@config)
    command.parse(["version=1.9.3", "encoding=utf-8"])
    command.exec(["version=1.9.3", "encoding=utf-8"], {:prefix=>@prefix, :capi => false}).returns(nil)
    @runner.run(["init", "version=1.9.3", "encoding=utf-8"])
  end

  def test_run_list
    command = mock(Object.new)
    mock(::BitClust::Subcommands::ListCommand).new.returns(command)
    mock(@runner).load_config.returns(@config)
    command.parse(["--library"])
    command.exec(["--library"], {:prefix=>@prefix, :capi => false})
    @runner.run(["list", "--library"])
  end

  def test_run_lookup
    command = mock(Object.new)
    mock(::BitClust::Subcommands::ListCommand).new.returns(command)
    mock(@runner).load_config.returns(@config)
    command.parse(["--library=optparse"])
    command.exec(["--library=optparse"], {:prefix=>@prefix, :capi => false})
    @runner.run(["list", "--library=optparse"])
  end

  def test_run_searcher
    command = mock(Object.new)
    mock(::BitClust::Searcher).new.returns(command)
    mock(@runner).load_config.returns(@config)
    command.parse(["String#gsub"])
    command.exec(["String#gsub"], {:prefix=>@prefix, :capi => false})
    @runner.run(["search", "String#gsub"])
  end

  def test_run_query
    command = mock(Object.new)
    mock(::BitClust::Subcommands::QueryCommand).new.returns(command)
    mock(@runner).load_config.returns(@config)
    command.parse(["db.properties"])
    command.exec(["db.properties"], {:prefix=>@prefix, :capi => false})
    @runner.run(["query", "db.properties"])
  end

  def test_run_update
    command = mock(Object.new)
    mock(::BitClust::Subcommands::UpdateCommand).new.returns(command)
    mock(@runner).load_config.returns(@config)
    command.parse(["_builtin/String"])
    command.exec(["_builtin/String"], {:prefix=>@prefix, :capi => false})
    @runner.run(["update", "_builtin/String"])
  end

  def test_run_property
    command = mock(Object.new)
    mock(::BitClust::Subcommands::PropertyCommand).new.returns(command)
    mock(@runner).load_config.returns(@config)
    command.parse(["--list"])
    command.exec(["--list"], {:prefix=>@prefix, :capi => false})
    @runner.run(["property", "--list"])
  end
end

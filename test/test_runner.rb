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
    mock(::BitClust::SetupCommand).new.returns(command)
    command.parse([])
    command.exec(nil, []).returns(nil)
    @runner.run(["setup"])
  end

  def test_run_server
    command = mock(Object.new)
    mock(::BitClust::ServerCommand).new.returns(command)
    command.parse([])
    command.exec(nil, []).returns(nil)
    @runner.run(["server"])
  end

  def test_run_init
    command = mock(Object.new)
    mock(::BitClust::InitCommand).new.returns(command)
    mock(@runner).load_config.returns(@config)
    mock(BitClust::MethodDatabase).new(@prefix).returns(@db)
    command.parse(["version=1.9.3", "encoding=utf-8"])
    command.exec(@db, ["version=1.9.3", "encoding=utf-8"]).returns(nil)
    @runner.run(["init", "version=1.9.3", "encoding=utf-8"])
  end

  def test_run_list
    command = mock(Object.new)
    mock(::BitClust::ListCommand).new.returns(command)
    mock(@runner).load_config.returns(@config)
    mock(BitClust::MethodDatabase).new(@prefix).returns(@db)
    command.parse(["--library"])
    command.exec(@db, ["--library"])
    @runner.run(["list", "--library"])
  end

  def test_run_lookup
    command = mock(Object.new)
    mock(::BitClust::ListCommand).new.returns(command)
    mock(@runner).load_config.returns(@config)
    mock(BitClust::MethodDatabase).new(@prefix).returns(@db)
    command.parse(["--library=optparse"])
    command.exec(@db, ["--library=optparse"])
    @runner.run(["list", "--library=optparse"])
  end

  def test_run_searcher
    command = mock(Object.new)
    mock(::BitClust::Searcher).new.returns(command)
    mock(@runner).load_config.returns(@config)
    mock(BitClust::MethodDatabase).new(@prefix).returns(@db)
    command.parse(["String#gsub"])
    command.exec(@db, ["String#gsub"])
    @runner.run(["search", "String#gsub"])
  end

  def test_run_query
    command = mock(Object.new)
    mock(::BitClust::QueryCommand).new.returns(command)
    mock(@runner).load_config.returns(@config)
    mock(BitClust::MethodDatabase).new(@prefix).returns(@db)
    command.parse(["db.properties"])
    command.exec(@db, ["db.properties"])
    @runner.run(["query", "db.properties"])
  end

  def test_run_update
    command = mock(Object.new)
    mock(::BitClust::UpdateCommand).new.returns(command)
    mock(@runner).load_config.returns(@config)
    mock(BitClust::MethodDatabase).new(@prefix).returns(@db)
    command.parse(["_builtin/String"])
    command.exec(@db, ["_builtin/String"])
    @runner.run(["update", "_builtin/String"])
  end

  def test_run_property
    command = mock(Object.new)
    mock(::BitClust::PropertyCommand).new.returns(command)
    mock(@runner).load_config.returns(@config)
    mock(BitClust::MethodDatabase).new(@prefix).returns(@db)
    command.parse(["--list"])
    command.exec(@db, ["--list"])
    @runner.run(["property", "--list"])
  end
end

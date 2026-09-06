require 'bitclust'
require 'bitclust/runner'
require 'bitclust/user_dirs'
require 'tmpdir'
require 'fileutils'

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

  def test_run_search_without_database
    # search (Searcher) は自前で DB を探すので、--database も config も
    # なしで実行できる
    command = mock(Object.new)
    mock(::BitClust::Searcher).new.returns(command)
    mock(@runner).load_config.returns(nil)
    command.parse(["String#gsub"])
    command.exec(["String#gsub"], {:prefix => nil, :capi => false})
    @runner.run(["search", "String#gsub"])
  end

  def test_run_database_command_without_database
    # DB 必須のサブコマンドは、裸の raise ではなく案内付きのエラーで中断する
    command = mock(Object.new)
    mock(::BitClust::Subcommands::InitCommand).new.returns(command)
    mock(@runner).load_config.returns(nil)
    command.parse([])
    command.needs_database?.returns(true)
    original_stderr = $stderr
    $stderr = StringIO.new
    assert_raise(SystemExit) { @runner.run(["init"]) }
    message = $stderr.string
    assert_include(message, "--database (-d)")
    assert_include(message, "bitclust setup")
    assert_include(message, BitClust::UserDirs.config_candidates.join(' or '))
  ensure
    $stderr = original_stderr
  end

  def test_needs_database
    # グローバル --database が不要なサブコマンド
    # (DB を使わない・自前の -d を持つ・DB が任意)
    [
      BitClust::Subcommands::SetupCommand,
      BitClust::Subcommands::PreprocCommand,
      BitClust::Subcommands::ExtractCommand,
      BitClust::Subcommands::ClassesCommand,
      BitClust::Subcommands::MethodsCommand,
      BitClust::Subcommands::AncestorsCommand,
      BitClust::Subcommands::HtmlfileCommand,
      BitClust::Subcommands::SearchpageCommand,
    ].each do |klass|
      assert_false(klass.new.needs_database?, klass.name)
    end
    # グローバル --database が必須のサブコマンド
    [
      BitClust::Subcommands::InitCommand,
      BitClust::Subcommands::UpdateCommand,
      BitClust::Subcommands::ListCommand,
    ].each do |klass|
      assert_true(klass.new.needs_database?, klass.name)
    end
  end
end

# Runner#load_config が UserDirs 経由で設定ファイルを読むこと(実ファイルで検証)。
#
# テストリスト:
# [x] XDG の場所(~/.config/bitclust/config)にあればそれを読む
# [x] 従来の場所(~/.bitclust/config)にあればそれを読む
# [x] どちらも無ければ nil
class TestRunnerLoadConfig < Test::Unit::TestCase
  ENV_KEYS = %w[HOME XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME
                REFE2_SERVER BITCLUST_SERVER REFE2_DATADIR BITCLUST_DATADIR].freeze

  def setup
    @saved = ENV_KEYS.to_h {|k| [k, ENV[k]] }
    @home = Dir.mktmpdir
    ENV['HOME'] = @home
    (ENV_KEYS - %w[HOME]).each {|k| ENV.delete(k) }
    @runner = BitClust::Runner.new
  end

  def teardown
    @saved.each {|k, v| v ? ENV[k] = v : ENV.delete(k) }
    FileUtils.rm_rf(@home)
  end

  def write_config(path, prefix, version)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, { :default_version => version, :database_prefix => prefix }.to_yaml)
  end

  def test_load_config_from_xdg_location
    write_config(File.join(@home, '.config', 'bitclust', 'config'), '/xdg/db', '4.0')
    config = @runner.load_config
    assert_equal('/xdg/db', config[:database_prefix])
    assert_equal('4.0', config[:default_version])
  end

  def test_load_config_from_legacy_location
    write_config(File.join(@home, '.bitclust', 'config'), '/legacy/db', '3.4')
    config = @runner.load_config
    assert_equal('/legacy/db', config[:database_prefix])
    assert_equal('3.4', config[:default_version])
  end

  def test_load_config_prefers_xdg_over_legacy
    write_config(File.join(@home, '.bitclust', 'config'), '/legacy/db', '3.4')
    write_config(File.join(@home, '.config', 'bitclust', 'config'), '/xdg/db', '4.0')
    config = @runner.load_config
    assert_equal('/xdg/db', config[:database_prefix])
  end

  def test_load_config_nil_without_any_config_file
    assert_nil(@runner.load_config)
  end
end

# frozen_string_literal: true
require 'test/unit'
require 'bitclust'
require 'bitclust/subcommands/setup_command'
require 'bitclust/user_dirs'
require 'tmpdir'
require 'fileutils'
require 'yaml'

# setup サブコマンドの既定バージョン。
#
# テストリスト:
# [x] 既定の対象バージョンに teeny が付いていない
#     (#%if (version == "V") や #%version V の等値ゲートは文字列一致なので、
#     teeny 付きの版名で DB を作ると doctree CI・生成済みドキュメントと
#     ゲートの判定がずれる)
class TestSetupCommand < Test::Unit::TestCase
  def test_default_versions_have_no_teeny
    versions = BitClust::Subcommands::SetupCommand.new.instance_variable_get(:@versions)
    assert_false(versions.empty?)
    versions.each do |version|
      assert_match(/\A\d+\.\d+\z/, version)
    end
  end
end

# setup サブコマンドが選ぶ、設定・DB・doctree checkout の置き場所。
#
# テストリスト:
# [x] 何も無ければ XDG の場所(~/.config/bitclust, ~/.local/share/bitclust)を使う
# [x] 従来の ~/.bitclust/config だけあれば、そのレイアウトを維持する
# [x] 両方あれば XDG を使う
class TestSetupCommandLayout < Test::Unit::TestCase
  ENV_KEYS = %w[HOME XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME].freeze

  def setup
    @saved = ENV_KEYS.to_h {|k| [k, ENV[k]] }
    @home = Dir.mktmpdir
    ENV['HOME'] = @home
    (ENV_KEYS - %w[HOME]).each {|k| ENV.delete(k) }
    @cmd = BitClust::Subcommands::SetupCommand.new
  end

  def teardown
    @saved.each {|k, v| v ? ENV[k] = v : ENV.delete(k) }
    FileUtils.rm_rf(@home)
  end

  def touch_config(path)
    FileUtils.mkdir_p(File.dirname(path))
    FileUtils.touch(path)
  end

  def test_layout_uses_xdg_when_nothing_exists
    config_path, database_prefix, rubydoc_dir = @cmd.send(:layout)
    assert_equal(File.join(@home, '.config', 'bitclust', 'config'), config_path.to_s)
    assert_equal(File.join(@home, '.local', 'share', 'bitclust', 'db'), database_prefix)
    assert_equal(File.join(@home, '.local', 'share', 'bitclust', 'rubydoc'), rubydoc_dir.to_s)
  end

  def test_layout_keeps_legacy_when_only_legacy_config_exists
    touch_config(File.join(@home, '.bitclust', 'config'))
    config_path, database_prefix, rubydoc_dir = @cmd.send(:layout)
    assert_equal(File.join(@home, '.bitclust', 'config'), config_path.to_s)
    assert_equal(File.join(@home, '.bitclust', 'db'), database_prefix)
    assert_equal(File.join(@home, '.bitclust', 'rubydoc'), rubydoc_dir.to_s)
  end

  def test_layout_uses_xdg_when_both_exist
    touch_config(File.join(@home, '.bitclust', 'config'))
    touch_config(File.join(@home, '.config', 'bitclust', 'config'))
    config_path, database_prefix, _rubydoc_dir = @cmd.send(:layout)
    assert_equal(File.join(@home, '.config', 'bitclust', 'config'), config_path.to_s)
    assert_equal(File.join(@home, '.local', 'share', 'bitclust', 'db'), database_prefix)
  end
end

# setup --prepare が layout の選択どおりに設定ファイルを書くこと
# (checkout はネットワークに出るのでスタブする)
class TestSetupCommandPrepare < Test::Unit::TestCase
  ENV_KEYS = %w[HOME XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME].freeze

  def setup
    @saved = ENV_KEYS.to_h {|k| [k, ENV[k]] }
    @home = Dir.mktmpdir
    ENV['HOME'] = @home
    (ENV_KEYS - %w[HOME]).each {|k| ENV.delete(k) }
    @cmd = BitClust::Subcommands::SetupCommand.new
    stub(@cmd).checkout {|_dir| nil }
  end

  def teardown
    @saved.each {|k, v| v ? ENV[k] = v : ENV.delete(k) }
    FileUtils.rm_rf(@home)
  end

  def test_prepare_writes_config_under_xdg_config_home
    @cmd.send(:prepare)
    config_path = File.join(@home, '.config', 'bitclust', 'config')
    assert_true(File.exist?(config_path))
    config = YAML.load_file(config_path)
    assert_equal(File.join(@home, '.local', 'share', 'bitclust', 'db'), config[:database_prefix])
  end

  def test_prepare_keeps_legacy_layout_when_legacy_config_exists
    legacy_config = File.join(@home, '.bitclust', 'config')
    FileUtils.mkdir_p(File.dirname(legacy_config))
    versions = @cmd.instance_variable_get(:@versions)
    File.write(legacy_config, {
      :database_prefix => File.join(@home, '.bitclust', 'db'),
      :encoding        => 'utf-8',
      :versions        => versions,
      :default_version => versions.max,
      :mdtree          => File.join(@home, '.bitclust', 'rubydoc', 'manual', 'api'),
      :capi_mdtree     => File.join(@home, '.bitclust', 'rubydoc', 'manual', 'capi'),
      :baseurl         => 'http://localhost:10080',
      :port            => '10080',
      :pid_file        => '/tmp/bitclust.pid',
    }.to_yaml)
    @cmd.send(:prepare)
    assert_false(File.exist?(File.join(@home, '.config', 'bitclust', 'config')))
    config = YAML.load_file(legacy_config)
    assert_equal(File.join(@home, '.bitclust', 'db'), config[:database_prefix])
  end
end

# setup --purge が新旧すべての置き場所を消すこと
class TestSetupCommandPurge < Test::Unit::TestCase
  ENV_KEYS = %w[HOME XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME].freeze

  def setup
    @saved = ENV_KEYS.to_h {|k| [k, ENV[k]] }
    @home = Dir.mktmpdir
    ENV['HOME'] = @home
    (ENV_KEYS - %w[HOME]).each {|k| ENV.delete(k) }
    @cmd = BitClust::Subcommands::SetupCommand.new
  end

  def teardown
    @saved.each {|k, v| v ? ENV[k] = v : ENV.delete(k) }
    FileUtils.rm_rf(@home)
  end

  def test_purge_removes_legacy_xdg_config_data_and_cache_dirs
    dirs = [
      File.join(@home, '.bitclust'),
      File.join(@home, '.config', 'bitclust'),
      File.join(@home, '.local', 'share', 'bitclust'),
      File.join(@home, '.cache', 'bitclust'),
    ]
    dirs.each {|dir| FileUtils.mkdir_p(dir) }
    out, _err = capture_output do
      assert_raise(SystemExit) { @cmd.send(:purge) }
    end
    dirs.each do |dir|
      assert_false(File.exist?(dir), dir)
      assert_include(out, dir)
    end
  end

  def test_purge_is_fine_when_nothing_exists
    assert_raise(SystemExit) { capture_output { @cmd.send(:purge) } }
  end
end

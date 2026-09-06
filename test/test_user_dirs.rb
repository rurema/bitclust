# frozen_string_literal: true
require 'test/unit'
require 'tmpdir'
require 'fileutils'
require 'bitclust/user_dirs'

# 設定・DB・キャッシュの置き場所(XDG 準拠+従来の ~/.bitclust fallback)。
#
# テストリスト:
# [x] XDG_* 未設定なら ~/.config ~/.local/share ~/.cache の下の bitclust/
# [x] XDG_* が絶対パスならそれを使う。相対パスは無視して既定に戻る
# [x] config_file は XDG → ~/.bitclust の順で存在するものを返す。無ければ nil
# [x] load_config は設定ファイルの YAML を返す。無ければ nil
class TestUserDirs < Test::Unit::TestCase
  KEYS = %w[HOME XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME].freeze

  def setup
    @saved = KEYS.to_h {|k| [k, ENV[k]] }
    @home = Dir.mktmpdir
    ENV['HOME'] = @home
    %w[XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME].each {|k| ENV.delete(k) }
  end

  def teardown
    @saved.each {|k, v| v ? ENV[k] = v : ENV.delete(k) }
    FileUtils.rm_rf(@home)
  end

  def test_defaults_under_home
    assert_equal(File.join(@home, '.config', 'bitclust'), BitClust::UserDirs.config_home.to_s)
    assert_equal(File.join(@home, '.local', 'share', 'bitclust'), BitClust::UserDirs.data_home.to_s)
    assert_equal(File.join(@home, '.cache', 'bitclust'), BitClust::UserDirs.cache_home.to_s)
    assert_equal(File.join(@home, '.bitclust'), BitClust::UserDirs.legacy_dir.to_s)
  end

  def test_xdg_environment_variables
    ENV['XDG_CONFIG_HOME'] = File.join(@home, 'cfg')
    ENV['XDG_DATA_HOME'] = File.join(@home, 'data')
    ENV['XDG_CACHE_HOME'] = 'relative/cache'
    assert_equal(File.join(@home, 'cfg', 'bitclust'), BitClust::UserDirs.config_home.to_s)
    assert_equal(File.join(@home, 'data', 'bitclust'), BitClust::UserDirs.data_home.to_s)
    assert_equal(File.join(@home, '.cache', 'bitclust'), BitClust::UserDirs.cache_home.to_s)
  end

  def test_config_file_prefers_xdg_then_legacy
    assert_nil(BitClust::UserDirs.config_file)
    legacy = File.join(@home, '.bitclust', 'config')
    FileUtils.mkdir_p(File.dirname(legacy))
    File.write(legacy, { default_version: '3.4', database_prefix: '/legacy/db' }.to_yaml)
    assert_equal(legacy, BitClust::UserDirs.config_file.to_s)
    assert_equal('/legacy/db', BitClust::UserDirs.load_config[:database_prefix])
    xdg = File.join(@home, '.config', 'bitclust', 'config')
    FileUtils.mkdir_p(File.dirname(xdg))
    File.write(xdg, { default_version: '4.0', database_prefix: '/xdg/db' }.to_yaml)
    assert_equal(xdg, BitClust::UserDirs.config_file.to_s)
    assert_equal('/xdg/db', BitClust::UserDirs.load_config[:database_prefix])
  end

  def test_load_config_without_file
    assert_nil(BitClust::UserDirs.load_config)
  end
end

require 'test/unit'
require 'bitclust'
require 'bitclust/screen'

class TestEOLWarning < Test::Unit::TestCase
  SRC = <<'HERE'
= class Hoge
hoge class
== Instance Methods
--- foo
foo method
HERE

  BANNER_TEXT = 'このマニュアルは既にメンテナンスが終了したバージョンの Ruby を対象としています。'
  LATEST_URL = 'https://docs.ruby-lang.org/ja/latest/'

  def render(manager_options)
    lib, = BitClust::RRDParser.parse(SRC, 'testlib')
    datadir = File.expand_path('../data/bitclust', __dir__)
    manager = BitClust::ScreenManager.new({
      :templatedir => "#{datadir}/template.offline",
      :catalogdir => "#{datadir}/catalog",
      :encoding => 'utf-8',
      :default_encoding => 'utf-8',
      :base_url => '',
      :target_version => '3.0'
    }.merge(manager_options))
    db = BitClust::MethodDatabase.dummy('version' => '3.0')
    manager.class_screen(lib.fetch_class('Hoge'), :database => db).body
  end

  def test_eol_warning_banner_is_shown_when_enabled
    html = render(:eol_warning => true)
    assert_include(html, BANNER_TEXT)
    assert_include(html, LATEST_URL)
  end

  def test_eol_warning_banner_is_hidden_by_default
    html = render({})
    assert_not_include(html, BANNER_TEXT)
    assert_not_include(html, LATEST_URL)
  end
end

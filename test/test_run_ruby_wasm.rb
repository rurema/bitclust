require 'test/unit'
require 'bitclust'
require 'bitclust/screen'

class TestRunRubyWasm < Test::Unit::TestCase
  SRC = <<'HERE'
= class Hoge
hoge class
== Instance Methods
--- foo
foo method
HERE

  WASM_URL = 'https://cdn.jsdelivr.net/npm/@ruby/3.4-wasm-wasi@2.9.3-2.9.4/dist/ruby+stdlib.wasm'
  META_TAG = %Q(<meta name="rurema-run-ruby-wasm" content="#{WASM_URL}">)

  def render(manager_options)
    lib, = BitClust::RRDParser.parse(SRC, 'testlib')
    datadir = File.expand_path('../data/bitclust', __dir__)
    manager = BitClust::ScreenManager.new({
      :templatedir => "#{datadir}/template.offline",
      :catalogdir => "#{datadir}/catalog",
      :encoding => 'utf-8',
      :default_encoding => 'utf-8',
      :base_url => '',
      :target_version => '3.4'
    }.merge(manager_options))
    db = BitClust::MethodDatabase.dummy('version' => '3.4')
    manager.class_screen(lib.fetch_class('Hoge'), :database => db).body
  end

  def test_run_script_is_loaded_when_enabled
    html = render(:run_ruby_wasm => WASM_URL)
    assert_include(html, META_TAG)
    assert_include(html, 'js/run.js')
  end

  def test_run_script_is_not_loaded_by_default
    html = render({})
    assert_not_include(html, 'rurema-run-ruby-wasm')
    assert_not_include(html, 'run.js')
  end

  def test_wasm_url_is_html_escaped
    html = render(:run_ruby_wasm => 'https://example.com/ruby.wasm?a=1&b="x"')
    assert_include(html, 'content="https://example.com/ruby.wasm?a=1&amp;b=&quot;x&quot;"')
  end

  def test_coexists_with_eol_warning
    html = render(:run_ruby_wasm => WASM_URL, :eol_warning => true)
    assert_include(html, META_TAG)
    assert_include(html, 'class="eol-warning"')
  end
end

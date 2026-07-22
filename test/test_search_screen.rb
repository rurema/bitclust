require 'test/unit'
require 'bitclust'
require 'bitclust/screen'

# Covers data/bitclust/template/search: the dynamic CGI search-results page
# rendered by `bitclust server`'s /search endpoint (SearchScreen). Distinct
# from the static client-side search index (SearchIndexGenerator, covered by
# test_search_index_generator.rb) -- this one builds its "Kernel.#mf"-style
# label directly in the template from klass.name + typemark + signature.
#
# bitclust#250: Ruby 4.0 以降のドキュメントでは module function の表記を
# 独自の「.#」から「?.」に変える(表示のみ、識別子は変えない)。
class TestSearchScreenModuleFunctionDisplay < Test::Unit::TestCase
  SRC = <<'HERE'
= module Kernel
description
== Module Functions
--- mf

説明
HERE

  def render(version)
    _lib, db = BitClust::RRDParser.parse(SRC, 'testlib', {'version' => version})
    entry = db.get_method(BitClust::MethodSpec.parse('Kernel.#mf'))
    datadir = File.expand_path('../data/bitclust', __dir__)
    manager = BitClust::ScreenManager.new(
      :templatedir => "#{datadir}/template",
      :catalogdir => "#{datadir}/catalog",
      :encoding => 'utf-8',
      :default_encoding => 'utf-8',
      :base_url => '',
      :target_version => version
    )
    manager.search_screen([entry], :database => db, :q => 'mf', :elapsed_time => 0.0).body
  end

  def test_module_function_shows_dot_hash_before_4_0
    html = render('3.4')
    assert_include(html, 'Kernel.#mf')
  end

  def test_module_function_switches_to_question_dot_at_4_0
    html = render('4.0')
    assert_include(html, 'Kernel?.mf')
    assert_not_include(html, 'Kernel.#mf')
  end
end

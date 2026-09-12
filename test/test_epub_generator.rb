# frozen_string_literal: true
require 'test/unit'
require 'tmpdir'
require 'fileutils'
require 'rexml/document'
require 'bitclust'
require 'bitclust/generators/epub'
require 'bitclust/screen'
require 'bitclust/subcommands/statichtml_command'

# contents.opf のマニフェストは、statichtml が OEBPS 以下に生成する
# class/method/library/doc/function ページと css/image リソースを
# すべて（ユニークな id で）列挙しなければならない（EPUB の仕様上必須）。
# 以前は class ページと nav.xhtml、決め打ちの
# "OEBPS/doc/index.html"（拡張子が誤り）だけしか載っていなかった。
class TestEpubGeneratorContentsOpf < Test::Unit::TestCase
  def build_epub_generator
    datadir = File.expand_path('../data/bitclust', __dir__)
    BitClust::Generators::EPUB.new(:templatedir => Pathname.new("#{datadir}/template.epub"))
  end

  def setup
    @dir = Dir.mktmpdir
    @epub_directory = Pathname.new(@dir)
    @oebps = @epub_directory + "OEBPS"
    FileUtils.mkdir_p(@oebps + "class")
    FileUtils.mkdir_p(@oebps + "method/-array/i")
    FileUtils.mkdir_p(@oebps + "doc")
    FileUtils.mkdir_p(@oebps + "library")
    FileUtils.mkdir_p(@oebps + "function")
    FileUtils.mkdir_p(@oebps + "images")

    File.write(@oebps + "class/-array.xhtml", "<html/>")
    File.write(@oebps + "class/index.xhtml", "<html/>") # クラス一覧ページ
    File.write(@oebps + "method/-array/i/each.xhtml", "<html/>")
    File.write(@oebps + "doc/index.xhtml", "<html/>") # マニュアルのトップページ
    File.write(@oebps + "doc/help.xhtml", "<html/>")
    File.write(@oebps + "library/index.xhtml", "<html/>")
    File.write(@oebps + "library/json.xhtml", "<html/>")
    File.write(@oebps + "function/index.xhtml", "<html/>")
    File.write(@oebps + "function/rb_ary_new.xhtml", "<html/>")
    File.write(@oebps + "style.css", "body{}")
    File.write(@oebps + "images/rurema.png", "\x89PNG\r\n")
    File.write(@epub_directory + "nav.xhtml", "<html/>")

    @generator = build_epub_generator
    @generator.send(:generate_contents_opf, @epub_directory)
    @opf_path = @epub_directory + "contents.opf"
    @xml = File.read(@opf_path)
    @doc = REXML::Document.new(@xml)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def items
    REXML::XPath.match(@doc, "//manifest/item")
  end

  def test_contents_opf_is_well_formed_xml
    assert_nothing_raised { REXML::Document.new(@xml) }
  end

  def test_manifest_lists_every_xhtml_page_under_oebps
    hrefs = items.map {|item| item.attributes['href'] }
    %w[
      OEBPS/class/-array.xhtml
      OEBPS/class/index.xhtml
      OEBPS/method/-array/i/each.xhtml
      OEBPS/doc/index.xhtml
      OEBPS/doc/help.xhtml
      OEBPS/library/index.xhtml
      OEBPS/library/json.xhtml
      OEBPS/function/index.xhtml
      OEBPS/function/rb_ary_new.xhtml
      nav.xhtml
    ].each do |href|
      assert_include(hrefs, href)
    end
  end

  def test_manifest_lists_non_xhtml_resources_that_exist
    hrefs = items.map {|item| item.attributes['href'] }
    assert_include(hrefs, "OEBPS/style.css")
    assert_include(hrefs, "OEBPS/images/rurema.png")
    style_item = items.find {|item| item.attributes['href'] == "OEBPS/style.css" }
    assert_equal("text/css", style_item.attributes['media-type'])
    image_item = items.find {|item| item.attributes['href'] == "OEBPS/images/rurema.png" }
    assert_equal("image/png", image_item.attributes['media-type'])
  end

  def test_manifest_item_ids_are_unique
    ids = items.map {|item| item.attributes['id'] }
    assert_equal(ids.size, ids.uniq.size, "duplicate manifest item ids: #{ids}")
  end

  def test_manifest_item_ids_are_valid_xml_ncnames
    ids = items.map {|item| item.attributes['id'] }
    assert_false(ids.empty?)
    ids.each do |id|
      assert_match(/\A[A-Za-z_][A-Za-z0-9_.-]*\z/, id, "not a valid NCName: #{id.inspect}")
    end
  end

  # doc/index.xhtml はマニフェスト中に決め打ちの id="index" として
  # 一度だけ登場し、doc 以下を走査する側から重複登録されない。
  def test_doc_index_is_listed_exactly_once_with_the_index_id
    index_items = items.select {|item| item.attributes['href'] == "OEBPS/doc/index.xhtml" }
    assert_equal(1, index_items.size)
    assert_equal("index", index_items.first.attributes['id'])
  end

  def test_manifest_references_xhtml_not_html_for_the_index
    hrefs = items.map {|item| item.attributes['href'] }
    assert_not_include(hrefs, "OEBPS/doc/index.html")
  end

  # 目次ページ (nav) ・マニュアルのトップページ・クラスページだけが
  # spine（読み進める順序）に載る。約 11,700 あるメソッドページなどを
  # spine に加えると読書順序が壊れるので、マニフェストには載るが spine
  # には載らない。
  def test_spine_still_excludes_method_library_doc_and_function_pages
    spine_idrefs = REXML::XPath.match(@doc, "//spine/itemref").map {|el| el.attributes['idref'] }
    assert_equal(%w[toc index], spine_idrefs.first(2))

    class_item_ids = items.select {|item| item.attributes['href'].to_s.start_with?('OEBPS/class/') }
                          .map {|item| item.attributes['id'] }
    assert_equal(%w[toc index] + class_item_ids, spine_idrefs)

    other_ids = items.map {|item| item.attributes['id'] } - %w[toc index] - class_item_ids
    assert_false(other_ids.empty?)
    other_ids.each do |id|
      assert_not_include(spine_idrefs, id)
    end
  end
end

# EPUB のパッケージ（contents.opf）に載る前に、statichtml が出力ルートへ
# 書く 2 行のリダイレクトスタブ（<meta http-equiv=refresh> + <a>、
# ルート要素を持たず XML として整形式でない）を消す。
class TestEpubGeneratorIndexStub < Test::Unit::TestCase
  def build_epub_generator
    datadir = File.expand_path('../data/bitclust', __dir__)
    BitClust::Generators::EPUB.new(:templatedir => Pathname.new("#{datadir}/template.epub"))
  end

  def setup
    @dir = Dir.mktmpdir
    @contents_directory = Pathname.new(@dir) + "OEBPS"
    FileUtils.mkdir_p(@contents_directory)
    @generator = build_epub_generator
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_removes_the_redirect_stub_statichtml_writes_at_the_root
    stub_path = @contents_directory + "index.xhtml"
    File.write(stub_path, "<meta http-equiv=\"refresh\" content=\"0; URL=doc/index.xhtml\">\n<a href=\"doc/index.xhtml\">Go</a>\n")
    assert_raise(REXML::ParseException) { REXML::Document.new(File.read(stub_path)) }

    @generator.send(:remove_index_stub, @contents_directory)

    assert_false(stub_path.exist?)
  end

  def test_is_a_noop_when_the_stub_is_absent
    stub_path = @contents_directory + "index.xhtml"
    assert_nothing_raised { @generator.send(:remove_index_stub, @contents_directory) }
    assert_false(stub_path.exist?)
  end

  # doc/index.xhtml (マニュアルのトップページ) と紛れないことを確認する
  def test_does_not_touch_the_doc_index_page
    doc_dir = @contents_directory + "doc"
    FileUtils.mkdir_p(doc_dir)
    doc_index = doc_dir + "index.xhtml"
    File.write(doc_index, "<html/>")
    @generator.send(:remove_index_stub, @contents_directory)
    assert_true(doc_index.exist?)
  end
end

# data/bitclust/template.epub/layout の <meta>/<link> が自己終了しておらず
# XHTML として整形式でなかった（bug 2）。また template.epub/class の
# インデックス一覧が escape_html を通さずメソッド名を出力していたため、
# "<=>" や "&" のようなメソッド名を含むページが整形式 XML にならなかった
# （bug 3、template.offline はエスケープ済み: commit 95e1475）。
#
# Screen#run_template は ERB 化したテンプレート本体をレシーバの
# self.class（ClassScreen / MethodScreen そのもの）に「respond_to? なら
# コンパイルしない」というガード付きでキャッシュする。同一プロセス内で
# template.offline 用の別テスト（例: test_class_screen.rb）が先に走ると、
# そちらのコンパイル結果を再利用してしまい、このテストが実際には
# template.epub を検証できなくなる（test_method_screen.rb に既知の注記
# あり）。
#
# 専用のサブクラスに分けるだけでは防げない: respond_to? は継承した
# メソッドにも true を返すので、スーパークラス（本物の ClassScreen /
# MethodScreen）側で他のテストが先に class_template 等をコンパイル済みだと、
# このサブクラスの run_template はガードに阻まれて自分の
# @template_repository（= template.epub）で再コンパイルしない。
# そこで、最初の render より前に明示的に def_method して
# class_template / method_template / layout をこのサブクラス自身に
# 直接定義しておく。直接定義されたメソッドは継承したものより優先されるので、
# 他のテストの実行順序に関係なく template.epub の内容を使わせられる。
class EpubTestClassScreen < BitClust::ClassScreen; end
class EpubTestMethodScreen < BitClust::MethodScreen; end
class EpubTestClassIndexScreen < BitClust::ClassIndexScreen; end

epub_template_repository = BitClust::TemplateRepository.new(
  "#{File.expand_path('../data/bitclust', __dir__)}/template.epub"
)
[
  [EpubTestClassScreen, 'class', 'class_template'],
  [EpubTestMethodScreen, 'method', 'method_template'],
  [EpubTestClassIndexScreen, 'class-index', 'class_index_template'],
].each do |klass, id, method_name|
  ERB.new(epub_template_repository.load(id)).def_method(klass, method_name, "#{id}.erb")
end
[EpubTestClassScreen, EpubTestMethodScreen, EpubTestClassIndexScreen].each do |klass|
  ERB.new(epub_template_repository.load('layout')).def_method(klass, 'layout', 'layout.erb')
end

class TestEpubTemplateWellFormedness < Test::Unit::TestCase
  SRC = <<'HERE'
= module Helper
比較演算子を提供するヘルパーモジュール
= class Spaceship < Object
extend Helper
比較演算子とビット演算子を持つサンプルクラス
== Instance Methods
--- <=>(other) -> Integer

比較する。

--- &(other) -> Spaceship

論理積を返す。
HERE

  def setup
    datadir = File.expand_path('../data/bitclust', __dir__)
    @lib, @db = BitClust::RRDParser.parse(SRC, 'testlib', { 'version' => '3.4' })
    urlmapper = BitClust::Subcommands::StatichtmlCommand::URLMapperEx.new(
      :suffix => '.xhtml',
      :css_url => 'style.css',
      :favicon_url => 'rurema.png'
    )
    urlmapper.bitclust_html_base = '..'
    @manager = BitClust::ScreenManager.new(
      :templatedir => "#{datadir}/template.epub",
      :catalogdir => "#{datadir}/catalog",
      :encoding => 'utf-8',
      :default_encoding => 'utf-8',
      :urlmapper => urlmapper,
      :target_version => '3.4'
    )
  end

  def class_entry
    @lib.fetch_class('Spaceship')
  end

  def method_entry(name)
    class_entry.fetch_method(BitClust::MethodSpec.parse("Spaceship##{name}"))
  end

  def render_class_page
    @manager.send(:new_screen, EpubTestClassScreen, class_entry, :database => @db).body
  end

  def render_method_page(name)
    @manager.send(:new_screen, EpubTestMethodScreen, [method_entry(name)], :database => @db).body
  end

  def render_class_index_page
    @manager.send(:new_screen, EpubTestClassIndexScreen, [class_entry], :database => @db).body
  end

  def test_class_page_escapes_spaceship_operator_in_the_index_list
    html = render_class_page
    assert_include(html, '&lt;=&gt;')
  end

  def test_class_page_escapes_ampersand_operator_in_the_index_list
    html = render_class_page
    # "&" 単体がエスケープされて "&amp;" として出る（リンクテキストの終端）
    assert_match(/&amp;<\/a>/, html)
  end

  def test_class_page_is_well_formed_xml
    html = render_class_page
    assert_nothing_raised { REXML::Document.new(html) }
  end

  def test_method_page_for_spaceship_operator_is_well_formed_xml
    html = render_method_page('<=>')
    assert_nothing_raised { REXML::Document.new(html) }
  end

  def test_method_page_for_ampersand_operator_is_well_formed_xml
    html = render_method_page('&')
    assert_nothing_raised { REXML::Document.new(html) }
  end

  def test_layout_void_elements_are_self_closing
    html = render_class_page
    assert_not_match(%r{<meta[^>]*[^/]>}, html)
    assert_not_match(%r{<link[^>]*[^/]>}, html)
  end

  # template.epub/class の "extend:" 行も <br>（非自己終了）を出しており、
  # そのクラスページ全体が整形式 XML にならなかった（実データベースの
  # Array・CSV クラスで再現した。どちらも extend/aliases 行を持つ）。
  def test_class_page_extend_line_uses_a_self_closing_br
    html = render_class_page
    assert_include(html, 'extend: ')
    assert_not_match(%r{<br[^>]*[^/]>}, html)
    assert_nothing_raised { REXML::Document.new(html) }
  end

  # template.epub/class-index には対応する <ul> の無い孤立した </ul> が
  # あり、実データベースで OEBPS/class/index.xhtml が整形式にならなかった
  # （template.offline/class-index にも同じ孤立タグがあるが、HTML5 として
  # 読まれる分には実害がないため未修正のまま。EPUB の XHTML では致命的）。
  def test_class_index_page_has_no_orphaned_closing_tag
    html = render_class_index_page
    assert_not_include(html, '</ul>')
    assert_nothing_raised { REXML::Document.new(html) }
  end
end

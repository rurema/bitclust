# frozen_string_literal: true
require 'test/unit'
require 'json'
require 'fileutils'
require 'bitclust'
require 'bitclust/methoddatabase'
require 'bitclust/subcommands/searchpage_command'

# searchpage サブコマンド: 複数バージョンの DB から /ja/search/ 置換用の
# 静的検索ページ一式（index.html + 統合 search_data.js + JS/CSS アセット）を
# 生成する。rurema-search（サーバ常駐の全文検索）のリタイア先。
#
# テストリスト:
# [x] 統合 index: 全版共通エントリは versions に全版、片方だけのものはその版のみ
# [x] index.html に search_versions（昇順）と検索 UI の要素が埋まる
# [x] vendored JS + NOTICE + search_page.js + search.css がコピーされる
# [x] ページ専用 UI なので search_init.js（ページ内ボックス用）は含めない
# [x] DB を持たない引数なし呼び出しはエラー
# [x] グローバル --database 不要（needs_database? が false）
class TestSearchpageCommand < Test::Unit::TestCase
  def setup
    @tmpdir = "searchpage_test_tmp"
    FileUtils.rm_rf(@tmpdir)
    @db34 = build_db('3.4', <<~'RD')
      description

      = class Foo < Object
      == Instance Methods
      --- foo
    RD
    @db41 = build_db('4.1', <<~'RD')
      description

      = class Foo < Object
      == Instance Methods
      --- foo
      --- bar
    RD
    @out = "#{@tmpdir}/out"
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def build_db(version, builtin_rd)
    root = "#{@tmpdir}/tree-#{version}/refm/api/src"
    FileUtils.mkdir_p("#{root}/_builtin")
    File.write("#{root}/LIBRARIES", "_builtin\n")
    File.write("#{root}/_builtin.rd", builtin_rd)
    prefix = "#{@tmpdir}/db-#{version}"
    db = BitClust::MethodDatabase.new(prefix)
    db.init
    db.transaction do
      db.propset('version', version)
      db.propset('encoding', 'utf-8')
    end
    db.transaction do
      db.update_by_stdlibtree(root)
    end
    prefix
  end

  def run_command(argv)
    cmd = BitClust::Subcommands::SearchpageCommand.new
    cmd.parse(argv)
    cmd.exec(argv, { prefix: nil, capi: false })
    cmd
  end

  def test_needs_no_global_database_option
    cmd = BitClust::Subcommands::SearchpageCommand.new
    assert_false cmd.needs_database?
  end

  def test_merged_index_versions
    run_command(["--outputdir=#{@out}", @db41, @db34])
    js = File.read("#{@out}/js/search_data.js")
    assert_match(/\Avar search_data = \{/, js)
    data = JSON.parse(js.sub(/\Avar search_data = /, '').sub(/;\z/, ''))
    foo = data['index'].find { |e| e['full_name'] == 'Foo#foo' }
    bar = data['index'].find { |e| e['full_name'] == 'Foo#bar' }
    klass = data['index'].find { |e| e['full_name'] == 'Foo' }
    assert_equal %w[3.4 4.1], foo['versions']
    assert_equal %w[4.1], bar['versions']
    assert_equal %w[3.4 4.1], klass['versions']
  end

  def test_merged_index_shows_module_functions_as_question_dot_only
    # bitclust#279 コメント対応: 版によって表示が ".#"(4.0 より前)と
    # "?."(4.0 以降)に割れる module function は、統合ページでは "?."
    # 表記の1エントリに合流させる(両表記が併記されるとわかりにくい)
    db33 = build_db('3.3', <<~'RD')
      description

      = module Kernel
      == Module Functions
      --- at_exit{ ... } -> Proc
      aaa
    RD
    db40 = build_db('4.0', <<~'RD')
      description

      = module Kernel
      == Module Functions
      --- at_exit{ ... } -> Proc
      aaa
    RD
    run_command(["--outputdir=#{@out}", db40, db33])
    js = File.read("#{@out}/js/search_data.js")
    data = JSON.parse(js.sub(/\Avar search_data = /, '').sub(/;\z/, ''))
    entries = data['index'].select { |e| e['name'] == 'at_exit' }
    assert_equal ['Kernel?.at_exit'], entries.map { |e| e['full_name'] }
    assert_equal %w[3.3 4.0], entries[0]['versions']
    assert_not_match(/Kernel\.#/, js)
  end

  def test_index_html_embeds_versions_and_ui
    run_command(["--outputdir=#{@out}", @db41, @db34])
    html = File.read("#{@out}/index.html")
    assert_match(/var search_versions = \["3\.4","4\.1"\];/, html)
    assert_match(/var search_version_base = "\.\.\/";/, html)
    assert_match(/id="search-field"/, html)
    assert_match(/id="search-results"/, html)
    assert_match(%r{js/search_data\.js}, html)
    assert_match(%r{js/search_page\.js}, html)
  end

  def test_assets_are_copied
    run_command(["--outputdir=#{@out}", @db41, @db34])
    %w[search_navigation.js search_ranker.js search_controller.js
       search_page.js NOTICE].each do |f|
      assert File.exist?("#{@out}/js/#{f}"), "js/#{f} not copied"
    end
    assert File.exist?("#{@out}/search.css")
    # ページ内ドロップダウン用の search_init.js はこのページでは使わない
    assert_false File.exist?("#{@out}/js/search_init.js")
  end

  def test_no_database_arguments_is_an_error
    cmd = BitClust::Subcommands::SearchpageCommand.new
    argv = ["--outputdir=#{@out}"]
    cmd.parse(argv)
    assert_raise(SystemExit) do
      capture_stderr { cmd.exec(argv, { prefix: nil, capi: false }) }
    end
  end

  def test_missing_outputdir_is_an_error
    cmd = BitClust::Subcommands::SearchpageCommand.new
    argv = [@db34]
    cmd.parse(argv)
    assert_raise(SystemExit) do
      capture_stderr { cmd.exec(argv, { prefix: nil, capi: false }) }
    end
  end

  private

  def capture_stderr
    orig = $stderr
    $stderr = StringIO.new
    yield
  ensure
    $stderr = orig
  end
end

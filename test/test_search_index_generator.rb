# frozen_string_literal: true
require 'test/unit'
require 'json'
require 'fileutils'
require 'tmpdir'
require 'bitclust'
require 'bitclust/methoddatabase'
require 'bitclust/search_index_generator'

class TestSearchIndexGenerator < Test::Unit::TestCase
  def setup
    @prefix = 'db_si'
    @base = 'tree_si'
    @root = "#{@base}/refm/api/src"
    setup_files
    @db = BitClust::MethodDatabase.new(@prefix)
    @db.init
    @db.transaction do
      [%w[version 3.4], %w[encoding utf-8]].each do |k, v|
        @db.propset(k, v)
      end
    end
    @db.transaction do
      @db.update_by_stdlibtree(@root)
    end
    @gen = BitClust::SearchIndexGenerator.new
  end

  def teardown
    FileUtils.rm_r([@prefix, @base], :force => true)
  end

  def find_entry(index, full_name)
    index.find { |e| e[:full_name] == full_name }
  end

  def test_class_entry
    index = @gen.build_index(@db)
    e = find_entry(index, 'Foo')
    assert_not_nil e
    assert_equal 'Foo', e[:name]
    assert_equal 'class', e[:type]
    assert_equal 'class/-foo.html', e[:path]
  end

  def test_module_entry_type
    index = @gen.build_index(@db)
    e = find_entry(index, 'Kernel')
    assert_not_nil e
    assert_equal 'module', e[:type]
    assert_equal 'class/-kernel.html', e[:path]
  end

  def test_instance_method_entry
    index = @gen.build_index(@db)
    e = find_entry(index, 'Foo#foo')
    assert_not_nil e
    assert_equal 'foo', e[:name]
    assert_equal 'instance_method', e[:type]
    assert_equal 'method/-foo/i/foo.html', e[:path]
  end

  def test_module_function_is_class_method
    index = @gen.build_index(@db)
    e = find_entry(index, 'Kernel.#at_exit')
    assert_not_nil e
    assert_equal 'at_exit', e[:name]
    assert_equal 'class_method', e[:type]
    assert_equal 'method/-kernel/m/at_exit.html', e[:path]
  end

  # bitclust#250: Ruby 4.0 以降のドキュメントでは module function の表記を
  # 独自の「.#」から「?.」に変える(表示のみ)。full_name は検索結果に
  # そのまま出る表示ラベルなので変換対象だが、path(識別子)は変えない
  def test_module_function_full_name_switches_to_question_dot_at_4_0
    prefix = 'db_si_40'
    base = 'tree_si_40'
    root = "#{base}/refm/api/src"
    FileUtils.mkdir_p("#{root}/_builtin")
    File.write("#{root}/LIBRARIES", "_builtin\n")
    File.write("#{root}/_builtin.rd", <<~RD)
      description

      = module Kernel
      description
      == Module Functions
      --- at_exit{ ... } -> Proc
      aaa
    RD
    db = BitClust::MethodDatabase.new(prefix)
    db.init
    db.transaction do
      [%w[version 4.0], %w[encoding utf-8]].each { |k, v| db.propset(k, v) }
    end
    db.transaction { db.update_by_stdlibtree(root) }

    index = BitClust::SearchIndexGenerator.new.build_index(db)
    e = index.find { |x| x[:path] == 'method/-kernel/m/at_exit.html' }
    assert_not_nil e
    assert_equal 'at_exit', e[:name]
    assert_equal 'class_method', e[:type]
    assert_equal 'Kernel?.at_exit', e[:full_name]
  ensure
    FileUtils.rm_r([prefix, base], :force => true)
  end

  def test_constant_entry
    index = @gen.build_index(@db)
    e = find_entry(index, 'Foo::AAA')
    assert_not_nil e
    assert_equal 'AAA', e[:name]
    assert_equal 'constant', e[:type]
    assert_equal 'method/-foo/c/-a-a-a.html', e[:path]
  end

  def test_special_variable_keeps_its_sigil_in_name
    # A special variable's "$" is part of how it is written and is the only
    # thing distinguishing it (there is no owning class to qualify it), so it
    # must stay in +name+ for a "$;"-style query to match. See issue #194.
    #
    # The +name+/+type+ assertions below are what issue #194 is about. The
    # +path+ assertion is secondary and filesystem-dependent: @gen defaults to
    # fs_casesensitive: false, so the path is built by encodename_fs ("Kernel"
    # -> "-kernel", ";" -> "=3b"). It is fine to ignore ONLY the path failure if
    # it broke because the fs encoding scheme changed or a case-sensitive build
    # (fs_casesensitive: true, giving "method/Kernel/v/...") is in use -- as long
    # as name/type still hold. A name/type failure is a real regression.
    index = @gen.build_index(@db)
    e = find_entry(index, '$;')
    assert_not_nil e
    assert_equal '$;', e[:name]
    assert_equal 'variable', e[:type]
    assert_equal 'method/-kernel/v/=3b.html', e[:path],
                 'filesystem-encoded path (fs_casesensitive: false); ' \
                 'ignore only this failure if just the fs encoding/casing changed'
  end

  def test_special_variable_word_name_keeps_its_sigil
    index = @gen.build_index(@db)
    e = find_entry(index, '$stdout')
    assert_not_nil e
    assert_equal '$stdout', e[:name]
    assert_equal 'variable', e[:type]
  end

  def test_same_method_name_in_two_classes
    index = @gen.build_index(@db)
    assert_not_nil find_entry(index, 'Foo#foo')
    assert_not_nil find_entry(index, 'Bar#foo')
  end

  def test_no_duplicate_paths
    index = @gen.build_index(@db)
    paths = index.map { |e| e[:path] }
    assert_equal paths.uniq.size, paths.size, 'index must not contain duplicate paths'
  end

  def test_document_entry_uses_title_and_slug
    index = @gen.build_index(@db)
    e = index.find { |x| x[:type] == 'document' && x[:path] == 'doc/glossary.html' }
    assert_not_nil e
    assert_equal 'Ruby用語集 (glossary)', e[:full_name]
    assert_equal 'Ruby用語集 (glossary)', e[:name]
  end

  # {#id}-anchored doc headings (rurema/doctree#2352: keywords like
  # defined?/undef/alias aren't methods, so they never show up in the
  # class/method-derived index -- they only show up via their doc page
  # heading). These need a native md doc tree (copy_doc_md), which is a
  # different ingestion path than the RD @root fixture set up in #setup, so
  # they build their own tiny db per case (mirrors test_copy_doc_md.rb).

  def build_md_doc_index(files)
    Dir.mktmpdir do |dir|
      files.each do |relpath, content|
        path = File.join(dir, 'manual', 'doc', relpath)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, content)
      end
      FileUtils.mkdir_p(File.join(dir, 'manual', 'api'))

      prefix = File.join(dir, 'db')
      db = BitClust::MethodDatabase.new(prefix)
      db.init
      db.transaction do
        db.propset('version', '3.4')
        db.propset('encoding', 'utf-8')
      end
      db.transaction do
        db.instance_variable_set(:@md_root, File.join(dir, 'manual', 'api'))
        db.__send__(:copy_doc_md)
      end
      # Reopen (like test_copy_doc_md.rb) rather than reuse the writer db,
      # so the index is built from what was actually persisted.
      db2 = BitClust::MethodDatabase.new(prefix)
      BitClust::SearchIndexGenerator.new.build_index(db2)
    end
  end

  def test_document_heading_entry_for_anchored_heading
    index = build_md_doc_index(
      'spec/def.md' => <<~MD
        # クラス／メソッドの定義

        本文。

        #### alias {#alias}

        alias の説明。

        #### undef {#undef}

        undef の説明。
      MD
    )
    e = index.find { |x| x[:type] == 'heading' && x[:name] == 'alias' }
    assert_not_nil e
    assert_equal 'alias (クラス／メソッドの定義)', e[:full_name]
    assert_equal 'doc/spec=2fdef.html#alias', e[:path]

    e2 = index.find { |x| x[:type] == 'heading' && x[:name] == 'undef' }
    assert_not_nil e2
    assert_equal 'doc/spec=2fdef.html#undef', e2[:path]
  end

  def test_heading_without_anchor_is_not_indexed
    index = build_md_doc_index(
      'spec/def.md' => <<~MD
        # クラス／メソッドの定義

        #### 見出し

        本文。
      MD
    )
    assert_nil index.find { |x| x[:type] == 'heading' }
  end

  def test_heading_inside_fenced_code_is_not_mistaken_for_a_heading
    # A "# ..." line at column 0 inside a ```ruby sample must not be
    # misdetected as an h1 just because it starts with "#".
    index = build_md_doc_index(
      'spec/control.md' => <<~MD
        # 制御構造

        #### if {#if}

        ```ruby
        # this is not a heading
        if true
          1
        end
        ```
      MD
    )
    headings = index.select { |x| x[:type] == 'heading' }
    assert_equal 1, headings.size
    assert_equal 'if', headings[0][:name]
  end

  def test_heading_label_strips_inline_code_span_backticks
    index = build_md_doc_index(
      'spec/comment.md' => <<~MD
        # コメント

        ### 文字列リテラルの凍結(`frozen_string_literal`) {#frozen_string_literal}

        本文。
      MD
    )
    e = index.find { |x| x[:type] == 'heading' }
    assert_not_nil e
    assert_equal '文字列リテラルの凍結(frozen_string_literal)', e[:name]
  end

  def test_to_js_format
    js = @gen.to_js(@db)
    assert_match(/\Avar search_data = \{/, js)
    assert(js.end_with?(';'), 'to_js output must end with a semicolon')

    json = js.sub(/\Avar search_data = /, '').sub(/;\z/, '')
    data = JSON.parse(json)
    assert_kind_of Array, data['index']
    assert(data['index'].any? { |e| e['full_name'] == 'Foo#foo' })
  end

  # 全バージョン対応の検索ページ用: 版ごとの index を versions タグ付きで統合する

  def entry(over = {})
    { name: 'Foo', full_name: 'Foo', type: 'class', path: 'class/-foo.html' }.merge(over)
  end

  def test_merge_dedupes_identical_entries_across_versions
    merged = BitClust::SearchIndexGenerator.merge(
      [['3.4', [entry]], ['3.0', [entry]]])
    assert_equal 1, merged.size
    assert_equal %w[3.0 3.4], merged[0][:versions]
    assert_equal 'Foo', merged[0][:full_name]
  end

  def test_merge_sorts_versions_numerically
    # "3.10" は文字列比較だと "3.4" より前に来てしまう
    merged = BitClust::SearchIndexGenerator.merge(
      [['4.1', [entry]], ['3.10', [entry]], ['3.4', [entry]]])
    assert_equal %w[3.4 3.10 4.1], merged[0][:versions]
  end

  def test_merge_keeps_entries_with_different_paths_separate
    a = entry(full_name: 'X#x', name: 'x', type: 'instance_method',
              path: 'method/-x/i/x.html')
    b = a.merge(path: 'method/=x/i/x.html')
    merged = BitClust::SearchIndexGenerator.merge([['3.4', [a]], ['4.1', [b]]])
    assert_equal 2, merged.size
    assert_equal [['3.4'], ['4.1']], merged.map { |e| e[:versions] }
  end

  def test_merge_orders_entries_by_first_appearance_in_version_order
    # 入力順に依らず「昇順の版を走査して最初に現れた順」で安定させる
    # （generated-documents にコミットされる出力の diff を安定させるため）
    a = entry(full_name: 'A', name: 'A', path: 'class/-a.html')
    b = entry(full_name: 'B', name: 'B', path: 'class/-b.html')
    merged = BitClust::SearchIndexGenerator.merge(
      [['3.4', [a, b]], ['3.0', [b]]])
    assert_equal %w[B A], merged.map { |e| e[:full_name] }
  end

  def test_merged_js_format
    js = BitClust::SearchIndexGenerator.merged_js([['3.4', [entry]]])
    assert_match(/\Avar search_data = \{/, js)
    assert(js.end_with?(';'))
    data = JSON.parse(js.sub(/\Avar search_data = /, '').sub(/;\z/, ''))
    assert_equal ['3.4'], data['index'][0]['versions']
    assert_equal 'Foo', data['index'][0]['full_name']
  end

  private

  def setup_files
    FileUtils.mkdir_p("#{@root}/_builtin")

    File.open("#{@root}/LIBRARIES", 'w+') do |file|
      file.puts '_builtin'
    end

    File.open("#{@root}/_builtin.rd", 'w+') do |file|
      file.puts <<'HERE'
description

= class Foo < Object
description
== Instance Methods
--- foo
== Constants
--- AAA
= class Bar < Object
== Instance Methods
--- foo
= module Kernel
description
== Module Functions
--- at_exit{ ... } -> Proc
aaa
== Special Variables
--- $; -> String | nil
区切り文字。
--- $stdout -> IO
標準出力。

HERE
    end

    # Prose doc pages are loaded from <stdlibtree>/../../doc/**/*.rd
    docdir = "#{@base}/refm/doc"
    FileUtils.mkdir_p(docdir)
    File.open("#{docdir}/glossary.rd", 'w+') do |file|
      file.puts '= Ruby用語集'
      file.puts
      file.puts '用語の説明。'
    end
  end
end

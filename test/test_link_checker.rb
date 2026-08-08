# frozen_string_literal: true

require 'test/unit'
require 'tmpdir'
require 'fileutils'
require 'bitclust'
require 'bitclust/methoddatabase'
require 'bitclust/link_checker'

# bitclust#286 派生の要望: [[c:]]/[[m:]] 等の参照は描画時に存在検証されず
# リンク切れが静かに発生するため、DB 全体を走査して壊れた参照を報告する
# LinkChecker を提供する。抽出は実際のコンパイル経路(bracket_link)を
# 使うので、コードスパン・フェンス内の参照風テキストは対象外になる。
class TestLinkChecker < Test::Unit::TestCase
  FOO_MD = <<~'MD'
    ---
    library: foo
    ---
    # class Foo < Object

    正しい参照: [c:Foo] と [m:Foo#bar] と [m:Foo.baz] と [m:Foo::CONST]
    と [lib:foo] と [d:spec/page]。

    壊れた参照: [c:Nope] と [m:Foo#nope] と [m:Nope#x] と [lib:nolib]
    と [d:spec/nope]。

    コードスパン内は対象外: `[c:CodeSpan]`。

    ```ruby
    # フェンス内も対象外: [m:Fence#no]
    ```

    ## Instance Methods

    ### def bar -> nil

    メソッド本文からの壊れた参照: [m:Foo#missing_from_method]

    ## Class Methods

    ### def Foo.baz -> nil

    baz です。

    ## Constants

    ### const CONST -> Integer

    定数です。
  MD

  def build_db(dir)
    api = File.join(dir, 'manual', 'api')
    FileUtils.mkdir_p(File.join(api, 'foo'))
    FileUtils.mkdir_p(File.join(dir, 'manual', 'doc', 'spec'))
    File.write(File.join(api, 'foo.md'),
               "---\ntype: library\n---\nライブラリ概要。壊れた参照: [c:AlsoNope]\n")
    File.write(File.join(api, 'foo', 'Foo.md'), FOO_MD)
    File.write(File.join(dir, 'manual', 'doc', 'spec', 'page.md'),
               "# ページ\n\ndoc からの壊れた参照: [m:Foo#doc_missing]。正しい参照: [c:Foo]。\n")

    prefix = File.join(dir, 'db')
    db = BitClust::MethodDatabase.new(prefix)
    db.init
    db.transaction do
      db.propset('version', '3.4')
      db.propset('encoding', 'utf-8')
    end
    db.transaction do
      db.update_by_markdowntree(api)
    end
    BitClust::MethodDatabase.new(prefix)
  end

  def test_check_all_reports_only_broken_refs
    Dir.mktmpdir do |dir|
      db = build_db(dir)
      findings = BitClust::LinkChecker.new(db).check_all
      refs = findings.map(&:ref).sort
      assert_equal(
        [
          'c:AlsoNope',
          'c:Nope',
          'd:spec/nope',
          'lib:nolib',
          'm:Foo#doc_missing',
          'm:Foo#missing_from_method',
          'm:Foo#nope',
          'm:Nope#x',
        ],
        refs
      )
    end
  end

  def test_findings_carry_location
    Dir.mktmpdir do |dir|
      db = build_db(dir)
      findings = BitClust::LinkChecker.new(db).check_all
      f = findings.find { |x| x.ref == 'm:Foo#nope' }
      assert_not_nil f
      assert_match(/Foo\.md/, f.location.to_s)
    end
  end

  def test_exit_style_summary
    Dir.mktmpdir do |dir|
      db = build_db(dir)
      checker = BitClust::LinkChecker.new(db)
      checker.check_all
      assert_equal 8, checker.broken_count
    end
  end
end

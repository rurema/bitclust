# frozen_string_literal: true
require 'test/unit'
require 'tmpdir'
require 'fileutils'
require 'stringio'
require 'bitclust'
require 'bitclust/methoddatabase'
require 'bitclust/subcommands/lookup_command'

# lookup サブコマンド(bitclust#294)。
#
# テストリスト:
# [x] --method --html が Markdown ソースの DB で HTML を返す
#     (シグネチャ dt に index_id の id 属性と permalink が付く)
# [x] --method --html が RD ソースの DB でも HTML を返す
# [x] --method(text)は従来どおりソースをそのまま出力する
# [x] --class --html は従来どおり動く
class TestLookupCommand < Test::Unit::TestCase
  FOO_MD = <<~'MD'
    ---
    library: foo
    ---
    # class Foo < Object

    クラスの説明。

    ## Instance Methods

    ### def bar -> nil

    bar の説明。
  MD

  FOO_RD = <<~'RD'
    description

    = class Foo < Object

    クラスの説明。

    == Instance Methods

    --- bar -> nil

    bar の説明。
  RD

  def build_markdown_db(dir)
    api = File.join(dir, 'manual', 'api')
    FileUtils.mkdir_p(File.join(api, 'foo'))
    File.write(File.join(api, 'foo.md'), "---\ntype: library\n---\nfoo ライブラリ。\n")
    File.write(File.join(api, 'foo', 'Foo.md'), FOO_MD)
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
    prefix
  end

  def build_rd_db(dir)
    root = File.join(dir, 'refm', 'api', 'src')
    FileUtils.mkdir_p(root)
    File.write(File.join(root, 'LIBRARIES'), "foo\n")
    File.write(File.join(root, 'foo.rd'), FOO_RD)
    prefix = File.join(dir, 'db')
    db = BitClust::MethodDatabase.new(prefix)
    db.init
    db.transaction do
      db.propset('version', '3.4')
      db.propset('encoding', 'utf-8')
    end
    db.transaction do
      db.update_by_stdlibtree(root)
    end
    prefix
  end

  def run_lookup(prefix, argv)
    cmd = BitClust::Subcommands::LookupCommand.new
    cmd.parse(argv)
    out = StringIO.new
    orig_stdout = $stdout
    $stdout = out
    begin
      cmd.exec([], { prefix: prefix, capi: false })
    ensure
      $stdout = orig_stdout
    end
    out.string
  end

  def test_method_html_on_markdown_db
    Dir.mktmpdir do |dir|
      prefix = build_markdown_db(dir)
      html = run_lookup(prefix, ['--method', 'Foo#bar', '--html'])
      assert_match(/<dt class="method-heading" id="[^"]+"><code>bar/, html)
      assert_match(/permalink/, html)
      assert_match(/bar の説明。/, html)
    end
  end

  def test_method_html_on_rd_db
    Dir.mktmpdir do |dir|
      prefix = build_rd_db(dir)
      html = run_lookup(prefix, ['--method', 'Foo#bar', '--html'])
      assert_match(/<dt class="method-heading" id="[^"]+"><code>bar/, html)
      assert_match(/permalink/, html)
      assert_match(/bar の説明。/, html)
    end
  end

  def test_method_text
    Dir.mktmpdir do |dir|
      prefix = build_markdown_db(dir)
      text = run_lookup(prefix, ['--method', 'Foo#bar'])
      assert_match(/\Atype: instance_method$/, text)
      assert_match(/^### def bar -> nil$/, text)
    end
  end

  def test_class_html
    Dir.mktmpdir do |dir|
      prefix = build_markdown_db(dir)
      html = run_lookup(prefix, ['--class', 'Foo', '--html'])
      assert_match(%r{<dt>name</dt><dd>Foo</dd>}, html)
      assert_match(/クラスの説明。/, html)
    end
  end
end

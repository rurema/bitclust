# frozen_string_literal: true
require 'test/unit'
require 'stringio'
require 'tmpdir'
require 'fileutils'
require 'bitclust'
require 'bitclust/subcommands/htmlfile_command'

# htmlfile サブコマンドの Markdown ソース(manual/)の変換。
#
# テストリスト:
# [x] エンティティ md は front matter の library: を所属として変換する
# [x] library: が多重所属なら、その版で生きている先頭の所属を使う
# [x] library: が無く --library も無ければエラー
# [x] --library で所属を指定できる
# [x] ライブラリルート md(type: library)はファイル名をライブラリ名にする
# [x] --ruby の版で #%since が解決される
# [x] manual/doc/ の md は doc ページとして変換する
# [x] --capi の md は C API として変換する
# [x] RD ソースは RD として変換する
class TestHtmlfileCommand < Test::Unit::TestCase
  FOO_MD = <<~'MD'
    ---
    library: foo
    ---
    # class Foo < Object

    クラスの説明。

    ## Instance Methods

    ### def bar -> nil

    bar の **説明**。

    #%since 3.4
    ### def baz -> nil

    baz の説明。
    #%end
  MD

  def setup
    @tmpdir = Dir.mktmpdir
    @api = File.join(@tmpdir, 'manual', 'api')
    FileUtils.mkdir_p(File.join(@api, 'foo'))
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def write(rel, content)
    path = File.join(@tmpdir, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end

  def run_htmlfile(args, capi: false)
    cmd = BitClust::Subcommands::HtmlfileCommand.new
    argv = args.dup
    cmd.parse(argv)
    out = StringIO.new
    err = StringIO.new
    orig_out, orig_err = $stdout, $stderr
    $stdout, $stderr = out, err
    status = nil
    begin
      cmd.exec(argv, {:prefix => nil, :capi => capi})
    rescue SystemExit => e
      status = e.status
    ensure
      $stdout, $stderr = orig_out, orig_err
    end
    [out.string, err.string, status]
  end

  def test_entity_uses_library_in_front_matter
    path = write('manual/api/foo/Foo.md', FOO_MD)
    out, _err, status = run_htmlfile(['--ruby=3.4', '--target=Foo', path])
    assert_nil(status)
    assert_match(/class Foo/, out)
    assert_match(%r{library/foo">library foo<}, out)
    assert_match(%r{<strong>説明</strong>}, out)
  end

  def test_entity_uses_first_live_membership
    path = write('manual/api/foo/Foo.md', <<~'MD')
      ---
      library:
      #%until 3.4
        - old_foo
      #%end
        - foo
        - foo_ext
      ---
      # class Foo < Object

      クラスの説明。
    MD
    out, _err, status = run_htmlfile(['--ruby=3.4', '--target=Foo', path])
    assert_nil(status)
    assert_match(%r{library/foo">library foo<}, out)
    out, _err, _status = run_htmlfile(['--ruby=3.3', '--target=Foo', path])
    assert_match(%r{library/old_foo">library old_foo<}, out)
  end

  def test_entity_without_library_is_error
    path = write('manual/api/foo/Foo.md', FOO_MD.sub(/\A---\nlibrary: foo\n---\n/, ''))
    out, err, status = run_htmlfile(['--target=Foo', path])
    assert_equal(1, status)
    assert_equal('', out)
    assert_match(/library:/, err)
    assert_match(/--library/, err)
  end

  def test_library_option_gives_library
    path = write('manual/api/foo/Foo.md', FOO_MD.sub(/\A---\nlibrary: foo\n---\n/, ''))
    out, _err, status = run_htmlfile(['--library=bar', '--target=Foo', path])
    assert_nil(status)
    assert_match(%r{library/bar">library bar<}, out)
  end

  def test_library_root_uses_file_name
    write('manual/api/foo/Foo.md', FOO_MD)
    path = write('manual/api/net/foo.md', <<~'MD')
      ---
      type: library
      category: Network
      ---
      foo ライブラリの **説明**。
    MD
    out, _err, status = run_htmlfile([path])
    assert_nil(status)
    assert_match(%r{<h1>library net/foo</h1>}, out)
    assert_match(%r{<strong>説明</strong>}, out)
  end

  def test_builtin_library_root
    path = write('manual/api/_builtin.md', "---\ntype: library\n---\n組み込みライブラリ。\n")
    out, _err, status = run_htmlfile([path])
    assert_nil(status)
    assert_match(%r{<title>library _builtin }, out)
    assert_match(/組み込みライブラリ。/, out)
  end

  def test_ruby_version_resolves_gates
    path = write('manual/api/foo/Foo.md', FOO_MD)
    out, _err, _status = run_htmlfile(['--ruby=3.4', '--target=Foo', path])
    assert_match(/baz/, out)
    out, _err, _status = run_htmlfile(['--ruby=3.3', '--target=Foo', path])
    assert_match(/bar/, out)
    assert_not_match(/baz/, out)
  end

  def test_target_method
    path = write('manual/api/foo/Foo.md', FOO_MD)
    out, _err, status = run_htmlfile(['--ruby=3.4', '--target=Foo#bar', path])
    assert_nil(status)
    assert_match(/bar の <strong>説明<\/strong>/, out)
    assert_not_match(/baz の説明/, out)
  end

  def test_doc_page
    path = write('manual/doc/spec/foo.md', <<~'MD')
      # Foo の仕様

      本文の **強調**。
    MD
    out, _err, status = run_htmlfile([path])
    assert_nil(status)
    assert_match(/Foo の仕様/, out)
    assert_match(%r{本文の <strong>強調</strong>}, out)
  end

  def test_capi
    path = write('manual/capi/array.c.md', <<~'MD')
      ### VALUE rb_foo_new()

      空の **Foo** を作ります。

      ### VALUE rb_foo_bar(VALUE foo)

      bar を返します。
    MD
    out, _err, status = run_htmlfile(['--target=rb_foo_new', path], capi: true)
    assert_nil(status)
    assert_match(/rb_foo_new/, out)
    assert_match(%r{空の <strong>Foo</strong> を作ります。}, out)
    assert_not_match(/bar を返します/, out)
  end

  def test_rd_source
    path = write('refm/api/src/foo.rd', <<~'RD')
      = class Foo < Object

      クラスの説明。

      == Instance Methods

      --- bar -> nil

      bar の説明。
    RD
    out, _err, status = run_htmlfile(['--target=Foo', path])
    assert_nil(status)
    assert_match(/class Foo/, out)
    assert_match(/bar の説明。/, out)
  end
end

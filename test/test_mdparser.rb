# frozen_string_literal: true

require 'test/unit'
require 'stringio'
require 'fileutils'
require 'bitclust/mdparser'
require 'bitclust/rrdparser'
require 'bitclust/methoddatabase'

# MDParser: Markdown ソースを直接パースして DB エントリを作る（フェーズ3 M3）。
# 構造（クラス・エントリ・関係）は同等 rd の RRDParser と一致し、
# source には md 断片がそのまま入る。
class TestMDParser < Test::Unit::TestCase
  PARAMS = { "version" => "3.4" }

  def parse_md(md, libname = "_builtin")
    db = BitClust::MethodDatabase.dummy(PARAMS)
    lib = BitClust::MDParser.new(db).parse(StringIO.new(md), libname, PARAMS)
    [db, lib]
  end

  def parse_rd(rd, libname = "_builtin")
    db = BitClust::MethodDatabase.dummy(PARAMS)
    lib = BitClust::RRDParser.new(db).parse(StringIO.new(rd), libname, PARAMS)
    [db, lib]
  end

  def test_class_with_include_and_method
    md = <<~MD
      ---
      library: _builtin
      include:
        - Enumerable
      ---
      # class Array < Object

      配列クラス。

      ## Instance Methods

      ### def index(val) -> Integer

      説明。
    MD
    rd = <<~RD
      = class Array < Object
      include Enumerable

      配列クラス。

      == Instance Methods

      --- index(val) -> Integer

      説明。
    RD
    _, mlib = parse_md(md)
    _, rlib = parse_rd(rd)

    mc = mlib.classes.first
    rc = rlib.classes.first
    assert_equal rc.name, mc.name
    assert_equal rc.type, mc.type
    assert_equal rc.superclass&.name, mc.superclass&.name
    assert_equal rc.included.map(&:name), mc.included.map(&:name)
    assert_equal rc.entries.map(&:names), mc.entries.map(&:names)
    assert_equal rc.entries.first.type, mc.entries.first.type

    # source は md のまま
    assert_equal "配列クラス。", mc.source
    assert_equal "### def index(val) -> Integer\n\n説明。\n", mc.entries.first.source
  end

  def test_module_and_class_methods_section
    md = <<~MD
      ---
      library: _builtin
      ---
      # module Comparable

      比較演算モジュール。

      ## Class Methods

      ### def new -> Comparable

      生成。
    MD
    _, lib = parse_md(md)
    c = lib.classes.first
    assert_equal "Comparable", c.name
    assert_equal :module, c.type
    assert_equal :singleton_method, c.entries.first.type
  end

  def test_constants_section_with_const_keyword
    md = <<~MD
      ---
      library: _builtin
      ---
      # class Float < Numeric

      浮動小数点数。

      ## Constants

      ### const DIG -> Integer

      桁数。
    MD
    _, lib = parse_md(md)
    e = lib.classes.first.entries.first
    assert_equal :constant, e.type
    assert_equal ["DIG"], e.names
    assert_equal "### const DIG -> Integer\n\n桁数。\n", e.source
  end

  def test_reopen_with_dynamic_include_across_files
    # ライブラリはファイル単位で組み立てる（module 定義とreopen が別ファイル、
    # 同じ libname で順にパースすると同一 Library に合流する）
    module_md = <<~MD
      ---
      library: mylib
      ---
      # module MyModule

      モジュール。
    MD
    reopen_md = <<~MD
      ---
      library: mylib
      include:
        - MyModule
      ---
      # reopen Object
    MD
    db = BitClust::MethodDatabase.dummy(PARAMS)
    BitClust::MDParser.new(db).parse(StringIO.new(module_md), "mylib", PARAMS)
    BitClust::MDParser.new(db).parse(StringIO.new(reopen_md), "mylib", PARAMS)
    assert_equal ["MyModule"], db.get_class("Object").dynamically_included.map(&:name)
  end

  def test_gvar_signature
    md = <<~MD
      ---
      library: _builtin
      ---
      # module Kernel

      カーネル。

      ## Special Variables

      ### gvar $stdin -> IO

      標準入力。
    MD
    _, lib = parse_md(md)
    e = lib.classes.first.entries.first
    assert_equal :special_variable, e.type
    assert_equal "### gvar $stdin -> IO\n\n標準入力。\n", e.source
  end

  def test_relations_require_single_entity
    # 案B: 関係（include 等）を持つファイルは単一エンティティでなければならない
    md = <<~MD
      ---
      library: _builtin
      include:
        - Enumerable
      ---
      # class Foo < Object

      ふー。

      # class Bar < Object

      ばー。
    MD
    assert_raise(BitClust::ParseError) { parse_md(md) }
  end

  def test_library_file_with_category
    md = <<~MD
      ---
      type: library
      category: FileFormat
      ---
      CSV を扱うライブラリです。
    MD
    _, lib = parse_md(md, "csv")
    assert_equal "FileFormat", lib.category
    assert_equal "CSV を扱うライブラリです。", lib.source
  end

  def test_since_directive_in_body
    md = <<~MD
      ---
      library: _builtin
      ---
      # class Array < Object

      配列。

      ## Instance Methods

      \#@since 3.4
      ### def newmethod -> nil

      新しい。
      \#@end
    MD
    _, lib = parse_md(md)
    assert_equal [["newmethod"]], lib.classes.first.entries.map(&:names)
  end

  def test_update_by_markdowntree
    # MarkdownTree 駆動の組み立て: lib ファイル → メンバー（reopen 後置）、
    # 版ゲート外のライブラリ/メンバーはスキップ
    require 'tmpdir'
    Dir.mktmpdir do |root|
      write = ->(rel, s) {
        path = File.join(root, rel)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, s)
      }
      write.call('mylib.md', <<~MD)
        ---
        type: library
        category: Text
        ---
        mylib の説明。
      MD
      write.call('mylib/MyModule.md', <<~MD)
        ---
        library: mylib
        ---
        # module MyModule

        モジュール。
      MD
      # 辞書順で module より先に来る reopen ファイル（後置されることを確認）
      write.call('mylib/Kernel.md', <<~MD)
        ---
        library: mylib
        include:
          - MyModule
        ---
        # reopen Object
      MD
      write.call('mylib/Gone.md', <<~MD)
        ---
        library: mylib
        until: "3.0"
        ---
        # class Gone < Object

        3.0 で消えた。
      MD
      write.call('oldlib.md', <<~MD)
        ---
        type: library
        until: "2.0"
        ---
        古いライブラリ。
      MD

      db = BitClust::MethodDatabase.dummy(PARAMS)
      db.update_by_markdowntree(root)

      assert_equal ["mylib"], db.libraries.map(&:name)
      lib = db.fetch_library("mylib")
      assert_equal "Text", lib.category
      assert_equal "mylib の説明。", lib.source
      # reopen はメソッド定義が無い限り lib.classes に載らない（rd と同じ）
      assert_equal %w[MyModule], lib.classes.map(&:name).sort
      assert_equal ["MyModule"], db.get_class("Object").dynamically_included.map(&:name)
      # source_location は md の実パス
      assert_equal "#{root}/mylib.md", lib.source_location.file
      assert_equal "#{root}/mylib/MyModule.md", db.get_class("MyModule").source_location.file
    end
  end

  def test_multi_entity_bundle_without_relations
    md = <<~MD
      ---
      library: _builtin
      ---
      # class Errno::EPERM < SystemCallError

      EPERM。

      # class Errno::ENOENT < SystemCallError

      ENOENT。
    MD
    _, lib = parse_md(md)
    assert_equal %w[Errno::EPERM Errno::ENOENT], lib.classes.map(&:name)
  end
end

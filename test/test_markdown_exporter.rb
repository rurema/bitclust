# frozen_string_literal: true

require 'test/unit'
require 'stringio'
require 'bitclust'
require 'bitclust/markdown_exporter'
require 'bitclust/mdparser'
require 'bitclust/methoddatabase'
require 'bitclust/functiondatabase'
require 'bitclust/subcommands/statichtml_command'

# MarkdownExporter: statichtml --markdown-output 用に、HTML の各ページと
# 対になる Markdown を前処理済みソースから組み立てる。
class TestMarkdownExporter < Test::Unit::TestCase
  PARAMS = { "version" => "3.4" }

  def setup
    @urlmapper = BitClust::Subcommands::StatichtmlCommand::URLMapperEx.new(
      :suffix => '.html',
      :fs_casesensitive => true
    )
    @urlmapper.bitclust_html_base = '..'
    @exporter = BitClust::MarkdownExporter.new(@urlmapper, '.html')
  end

  def parse_md(md, libname = "_builtin")
    db = BitClust::MethodDatabase.dummy(PARAMS)
    lib = BitClust::MDParser.new(db).parse(StringIO.new(md), libname, PARAMS)
    [db, lib]
  end

  sub_test_case("convert_text") do
    def test_bare_method_ref
      assert_equal "[Array#index](../method/Array/i/index.md) を参照",
                   @exporter.convert_text("[m:Array#index] を参照")
    end

    def test_bare_class_ref
      assert_equal "[String](../class/String.md)",
                   @exporter.convert_text("[c:String]")
    end

    def test_bare_library_ref
      assert_equal "[csv](../library/csv.md)",
                   @exporter.convert_text("[lib:csv]")
    end

    def test_bare_doc_ref
      assert_equal "[spec/literal](../doc/spec=2fliteral.md)",
                   @exporter.convert_text("[d:spec/literal]")
    end

    def test_bare_function_ref
      assert_equal "[rb_ary_new](../function/rb_ary_new.md)",
                   @exporter.convert_text("[f:rb_ary_new]")
    end

    def test_module_function_ref
      # md 表記の ?. は内部表記 .# に正規化して URL を引く(ラベルは書かれたまま)
      assert_equal "[Kernel?.puts](../method/Kernel/m/puts.md)",
                   @exporter.convert_text("[m:Kernel?.puts]")
    end

    def test_method_ref_with_escaped_brackets
      # [m:Array#\[\]] のようにエスケープされた参照。URL はエスケープを解いた
      # メソッド名から引き、ラベルは書かれたまま(md として正しい形)を保つ
      assert_equal "[Array#\\[\\]](../method/Array/i/=5b=5d.md)",
                   @exporter.convert_text("[m:Array#\\[\\]]")
    end

    def test_labeled_ref
      assert_equal "[個数](../method/Array/i/size.md)",
                   @exporter.convert_text("[個数](m:Array#size)")
    end

    def test_labeled_ref_with_code_span_label
      assert_equal "[`Array#size`](../method/Array/i/size.md)",
                   @exporter.convert_text("[`Array#size`](m:Array#size)")
    end

    def test_markdown_link_kept
      assert_equal "[Ruby](https://www.ruby-lang.org/)",
                   @exporter.convert_text("[Ruby](https://www.ruby-lang.org/)")
    end

    def test_anchor_link_kept
      assert_equal "[前述の例](#example)",
                   @exporter.convert_text("[前述の例](#example)")
    end

    def test_url_ref
      assert_equal "[https://www.ruby-lang.org/](https://www.ruby-lang.org/)",
                   @exporter.convert_text("[url:https://www.ruby-lang.org/]")
    end

    def test_ref_in_page
      assert_equal "[overview](#overview)",
                   @exporter.convert_text("[ref:overview]")
    end

    def test_ref_cross_page
      assert_equal "[spec/literal#num](../doc/spec=2fliteral.md#num)",
                   @exporter.convert_text("[ref:d:spec/literal#num]")
    end

    def test_code_span_is_not_converted
      assert_equal "`[m:Array#index]`",
                   @exporter.convert_text("`[m:Array#index]`")
    end

    def test_code_fence_is_not_converted
      src = "```ruby\n# [m:Array#index]\n```\n[m:Array#index]\n"
      expected = "```ruby\n# [m:Array#index]\n```\n[Array#index](../method/Array/i/index.md)\n"
      assert_equal expected, @exporter.convert_text(src)
    end

    def test_unknown_ref_type_is_kept
      assert_equal "[man:printf(3)]", @exporter.convert_text("[man:printf(3)]")
    end

    def test_unresolvable_method_spec_is_kept
      # クラス名とメソッド名に分割できない指定はそのまま残す
      assert_equal "[m:broken spec]", @exporter.convert_text("[m:broken spec]")
    end

    def test_escaped_bracket_is_kept
      assert_equal "\\[m:Array#index]", @exporter.convert_text("\\[m:Array#index]")
    end
  end

  sub_test_case("pages") do
    CLASS_MD = <<~MD
      ---
      library: _builtin
      ---
      # class Array < Object

      配列クラス。[c:Enumerable] も参照。

      ## Class Methods

      ### def self.new(size) -> Array

      生成。

      ## Instance Methods

      ### def index(val) -> Integer
      ### def find_index(val) -> Integer

      位置を返します。
    MD

    def test_class_page
      _, lib = parse_md(CLASS_MD)
      md = @exporter.class_page(lib.classes.first)
      assert_equal <<~MD, md
        # class Array < Object

        配列クラス。[Enumerable](../class/Enumerable.md) も参照。

        ## Class Methods

        - [new](../method/Array/s/new.md)

        ## Instance Methods

        - [find_index](../method/Array/i/find_index.md)
        - [index](../method/Array/i/index.md)
      MD
    end

    def test_module_page_heading
      md = <<~MD
        ---
        library: _builtin
        ---
        # module Comparable

        比較。
      MD
      _, lib = parse_md(md)
      page = @exporter.class_page(lib.classes.first)
      assert page.start_with?("# module Comparable\n"), page
    end

    def test_method_page
      _, lib = parse_md(CLASS_MD)
      entry = lib.classes.first.entries.find { |e| e.names.include?("index") }
      @urlmapper.bitclust_html_base = '../../..'
      md = @exporter.method_page("Array#index", [entry])
      assert_equal <<~MD, md
        # Array#index

        ### def index(val) -> Integer
        ### def find_index(val) -> Integer

        位置を返します。
      MD
    end

    def test_method_page_normalizes_module_function_name
      _, lib = parse_md(CLASS_MD)
      entry = lib.classes.first.entries.first
      md = @exporter.method_page("Kernel.#puts", [entry])
      assert md.start_with?("# Kernel?.puts\n"), md
    end

    def test_library_page
      md = <<~MD
        ---
        type: library
        category: FileFormat
        ---
        CSV を扱うライブラリです。
      MD
      _, lib = parse_md(md, "csv")
      page = @exporter.library_page(lib)
      assert_equal <<~MD, page
        # library csv

        CSV を扱うライブラリです。
      MD
    end

    def test_doc_page
      db = BitClust::MethodDatabase.dummy(PARAMS)
      entry = BitClust::DocEntry.new(db, "help")
      entry.title = "ヘルプ"
      entry.source = "\n[c:String] を参照。\n"
      page = @exporter.doc_page(entry)
      assert_equal <<~MD, page
        # ヘルプ

        [String](../class/String.md) を参照。
      MD
    end

    def test_function_page
      require 'bitclust/functiondatabase'
      md = <<~MD
        ### VALUE rb_ary_new()

        空の配列を返します。
      MD
      db = BitClust::FunctionDatabase.dummy(PARAMS)
      io = StringIO.new(md)
      def io.path = "array.c.md"
      BitClust::MDFunctionParser.new(db).parse(io, "array.c", PARAMS)
      page = @exporter.function_page(db.functions.first)
      assert_equal <<~MD, page
        # rb_ary_new

        ### VALUE rb_ary_new()

        空の配列を返します。
      MD
    end
  end
end

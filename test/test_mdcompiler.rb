# frozen_string_literal: true

require 'bitclust/mdcompiler'
require 'bitclust/rdcompiler'
require 'bitclust/rrd_to_markdown'
require 'bitclust/database'
require 'bitclust/methoddatabase'
require 'bitclust/screen'
require 'test/unit'
require 'test/unit/rr'

# MDCompiler: Markdown ソース → HTML のネイティブコンパイラ（フェーズ3 M1）。
# M1 の不変条件: 変換器が生成する md に対して、対応する rd を RDCompiler に
# かけた場合と同一の HTML を出力する（等価モード）。
# GFM 拡張（テーブル・コードスパンの <code> 化等）は M2 で解禁する。
class TestMDCompiler < Test::Unit::TestCase
  def setup
    @dummy = 'dummy'
    @u = BitClust::URLMapper.new(Hash.new { @dummy })
    @db = BitClust::MethodDatabase.dummy("version" => "2.0.0")
    @md = BitClust::MDCompiler.new(@u, 1, { :database => @db })
    @rd = BitClust::RDCompiler.new(@u, 1, { :database => @db })
  end

  def compile_method(compiler, src)
    method_entry = Object.new
    mock(method_entry).source { src }
    mock(method_entry).index_id.any_times { "dummy" }
    mock(method_entry).defined?.any_times { true }
    mock(method_entry).id.any_times { "String/i.index._builtin" }
    compiler.compile_method(method_entry)
  end

  # rd ソースを両経路（rd 直接 / md 変換後）でコンパイルして等価を確認する
  def assert_equivalent_method(rd_src)
    md_src = BitClust::RRDToMarkdown.convert(rd_src)
    assert_equal compile_method(@rd, rd_src), compile_method(@md, md_src),
      "md source:\n#{md_src}"
  end

  def assert_equivalent_doc(rd_src)
    md_src = BitClust::RRDToMarkdown.convert(rd_src)
    assert_equal @rd.compile(rd_src), @md.compile(md_src), "md source:\n#{md_src}"
  end

  # ---- メソッドエントリ ----

  def test_method_signature_and_paragraph
    assert_equivalent_method <<~RD
      --- index(val) -> Integer

      説明文。
      2行目。
    RD
  end

  def test_multiple_signatures
    assert_equivalent_method <<~RD
      --- index(val) -> Integer
      --- index {|item| ... } -> Integer

      説明。
    RD
  end

  def test_param_return_raise
    assert_equivalent_method <<~RD
      --- index(val) -> Integer

      説明。

      @param val 探す値。
                 継続行。
      @return 位置。
      @raise TypeError 型が合わないとき。
    RD
  end

  def test_see
    assert_equivalent_method <<~RD
      --- index(val) -> Integer

      説明。

      @see [[m:Array#rindex]], [[m:Array#find_index]]
    RD
  end

  def test_inline_references
    assert_equivalent_method <<~RD
      --- index(val) -> Integer

      [[m:Array#rindex]] と [[c:String]] を参照。
      [[m:Hash#[] ]] のような括弧メソッドも。
    RD
  end

  def test_code_block_from_emlist
    assert_equivalent_method <<~RD
      --- index(val) -> Integer

      例:

      //emlist[例][ruby]{
      [1, 2].index(2) # => 1
      //}
    RD
  end

  def test_plain_emlist_block
    assert_equivalent_method <<~RD
      --- index(val) -> Integer

      //emlist{
      plain text art
      //}
    RD
  end

  def test_indented_code_block
    assert_equivalent_method <<~RD
      --- index(val) -> Integer

      例:

        [1, 2].index(2)
        # => 1

      続き。
    RD
  end

  def test_item_list
    assert_equivalent_method <<~RD
      --- index(val) -> Integer

      説明:

        * 項目1
        * 項目2
          継続行。
    RD
  end

  def test_dlist
    assert_equivalent_method <<~RD
      --- index(val) -> Integer

      : term1
        説明1。
      : term2
        説明2。
    RD
  end

  def test_entry_heading
    assert_equivalent_method <<~RD
      --- index(val) -> Integer

      説明。

      ===[a:anchor] 深掘り

      本文。
    RD
  end

  def test_const_signature
    assert_equivalent_method <<~RD
      --- INDEX_VERSION -> String

      定数の説明。
    RD
  end

  def test_param_description_with_example_block
    # CGI::HtmlExtension#popup_menu 型: 空白のみ行を挟む例示ブロックも @param の説明
    assert_equivalent_method <<~RD
      --- m(v) -> String

      説明。

      @param v 説明。

              例：
              code_like_text
    RD
  end

  def test_dlist_with_list_like_text_in_description
    # news/1.8.0 型: dd 内のリスト風テキストは RDCompiler ではただのテキスト
    assert_equivalent_doc <<~RD
      = タイトル

      : term
        説明。

            * 項目風1
            * 項目風2
    RD
  end

  def test_colon_line_as_paragraph_continuation
    # news/1.8.5 型: テキスト行直後の「: 」行は段落の継続
    assert_equivalent_doc <<~RD
      = タイトル

      以下が追加されました。
      : TCPServer#accept_nonblock [new]

      本文。
    RD
  end

  def test_list_item_with_shallow_continuation
    # news/2_6_0 型: 項目より浅い折り返しも項目の継続
    assert_equivalent_doc <<~RD
      = タイトル

        * 項目の一行目が長くて
         折り返した継続行。

      本文。
    RD
  end

  # ---- doc / ライブラリページ ----

  def test_doc_headline_and_paragraph
    assert_equivalent_doc <<~RD
      = タイトル

      本文段落。

      == 節

      節の本文。
    RD
  end

  def test_doc_lists_and_code
    assert_equivalent_doc <<~RD
      = タイトル

        * 項目1
        * 項目2

      //emlist[例][ruby]{
      p 1
      //}
    RD
  end

  def test_doc_dlist
    assert_equivalent_doc <<~RD
      = タイトル

      : 用語
        定義文。
    RD
  end
end

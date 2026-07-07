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

  def test_indented_code_with_tabs
    # Kernel#mkmf 型: タブは元のカラム位置で展開される（detab はデデント前）
    assert_equivalent_method "--- mkmf -> ()\n\n説明。\n\n  -d ARGS\trun dir_config\n  -h ARGS\trun have_header\n"
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

  def test_param_description_with_emlist
    # Array#pack 型: @param の説明に //emlist が続く（rd では dd の一部）
    assert_equivalent_method <<~RD
      --- m(v) -> String

      説明。

      @param v 値。

      //emlist[例][ruby]{
      p 1
      //}

      @return 結果。
    RD
  end

  def test_signature_without_space
    # OpenSSL::X509::Extension 型: 「---name」（スペース無し）を RDCompiler は受理する
    assert_equivalent_method <<~RD
      ---critical=(bool)
      重要度を設定します。

      @param bool 真偽値
    RD
  end

  def test_raise_without_description_trailing_space
    # Gem::RemoteFetcher#download 型: 「@raise Ex 」（説明なし・末尾スペース）
    # RDCompiler は dd 内に空白テキスト行を出す
    assert_equivalent_method "--- m(v) -> String\n\n説明。\n\n@raise SomeError \n"
  end

  def test_indented_code_across_double_blank
    # Process#exec 型: 空行2つを挟むインデントコードは1つの <pre> に融合する
    assert_equivalent_method <<~RD
      --- m(v) -> String

      例:

         exec "echo *"
         # never get here


         exec "echo", "*"
         # never get here

      @param v 値。
    RD
  end

  def test_undef_metadata
    # Complex#< 型: @undef は [UNKNOWN_META_INFO] として dl に描画される
    # （md でも生のまま渡る。MDCompiler が受けないと無限ループになる）
    assert_equivalent_method <<~RD
      --- <(other)    -> bool

      @undef
    RD
  end

  def test_unknown_metadata_after_param
    # @param に続く未知メタデータは同じ <dl> 内に UNKNOWN_META_INFO で入る
    assert_equivalent_method <<~RD
      --- m(v) -> bool

      説明。

      @param v 値。
      @undef
    RD
  end

  def test_dlist_description_with_interleaved_emlist
    # String#% 型: dd は「インデント段落 + emlist」を交互に何個でも受ける
    assert_equivalent_method <<~RD
      --- m(v) -> String

      : #
       プレフィックスを付けます。

      //emlist[][ruby]{
      p 1
      //}

       浮動小数点数に対しては必ず付けます。

      //emlist[][ruby]{
      p 2
      //}

      続き。
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

  def test_h5_heading
    # spec/safelevel 型: ===== は h3（hlevel 1 + (5-3)）として描画される
    assert_equivalent_doc <<~RD
      = タイトル

      ==== レベル 0

      ===== 汚染されるオブジェクト

      本文。
    RD
  end

  def test_olist_item_continuation
    # spec/terminate 型: (N) 項目の折り返し行は項目の継続
    assert_equivalent_doc <<~RD
      = タイトル

       (1) すべてのスレッドを kill
       (2) ハンドラが登録されていればそれを実
           行する。
       (3) 後始末。

      本文。
    RD
  end

  def test_see_in_doc_is_plain_text
    # pack_template 型: doc/lib ページの @see は RDCompiler では段落テキスト
    assert_equivalent_doc <<~RD
      = タイトル

      本文。

      @see [[c:String]]
    RD
  end

  def test_dlist_colon_term_without_space
    # spec/operator 型: dlist 継続の「:term」（スペース無し）も dt
    assert_equivalent_doc <<~RD
      = タイトル

      : 再定義できる演算子
        いろいろ。

      :再定義できない演算子
        これらは再定義できません。

      本文。
    RD
  end

  def test_colon_no_space_in_paragraph_stays_text
    # openssl/ASN1 型: 段落継続の「:SYMBOL」行は dlist 化しない
    assert_equivalent_doc <<~RD
      = タイトル

      タグクラスを返します。
      :IMPLICIT、:EXPLICIT、nil のいずれかを返します。

      本文。
    RD
  end

  def test_discrete_numbered_text
    # lib:logger 型: 離散した「N. テキスト」は RD では段落テキスト
    # （md では **N.** 太字。M1 では元のテキストに戻して描画する）
    assert_equivalent_doc <<~RD
      = タイトル

      ログの出力先について。

      1. STDERR/STDOUTに出力するように指定

      本文が続きます。

      2. ファイルに出力するように指定
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

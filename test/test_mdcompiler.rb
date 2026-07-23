# frozen_string_literal: true

require 'bitclust/mdcompiler'
require 'bitclust/rdcompiler'
require 'bitclust/rrd_to_markdown'
require 'bitclust/database'
require 'bitclust/methoddatabase'
require 'bitclust/screen'
require 'test/unit'
require 'test/unit/rr'
require 'stringio'

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
    mock(method_entry).names.any_times { [] }
    mock(method_entry).since_map.any_times { {} }
    mock(method_entry).until_map.any_times { {} }
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

  def capture_stderr
    orig = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = orig
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

  def test_inline_ref_with_hyphenated_fragment
    # [ref:d:page#frag] のフラグメントはハイフンを含められる
    # （doctree/manual の glossary.md 用語アンカー等、rd 直接/md 変換後で等価）
    assert_equivalent_method <<~RD
      --- index(val) -> Integer

      [[ref:d:hoge/bar#thread-safe]] を参照。
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

  def test_dlist_term_anchor
    # 用語の後ろの {#id} は dt のアンカー id になる（用語集の各用語リンク用, rurema/doctree#2634）
    html = @md.compile("- **アリティー**: {#arity}\n- **`arity`**:\n  仮引数の数。\n")
    assert_include(html, '<dt id="arity">アリティー</dt>')
    # {#id} が無い項目には id は付かない
    assert_not_include(html, '<dt id="arity">arity')
    # 通常の dlist は従来どおり id 無し
    plain = @md.compile("- **foo**:\n  bar\n")
    assert_include(plain, '<dt>foo</dt>')
    assert_not_include(plain, '<dt id')
  end

  def test_entry_heading
    assert_equivalent_method <<~RD
      --- index(val) -> Integer

      説明。

      ===[a:anchor] 深掘り

      本文。
    RD
  end

  def test_entry_heading_with_hyphenated_anchor
    # ハイフン入りアンカー（doctree/manual の glossary.md 用語アンカー等）でも
    # rd 直接コンパイルと md 変換後コンパイルが等価であること
    assert_equivalent_method <<~RD
      --- index(val) -> Integer

      説明。

      ===[a:thread-safe] スレッドセーフ

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

  def test_adjacent_fences_with_blank_line_merge
    # IO#sysseek 型: ゲート分断されたインデントブロックは版解決後に
    # 空白のみ行を挟む隣接フェンスとして現れる。rd の pre は空白行を
    # 跨ぐため、間の空白行ごと1つの <pre> にマージする
    rd_src = "--- m(v) -> String\n\n説明。\n\n" \
             "  line1\n  # => result\n  \n\n  line2\n"
    md_src = "### def m(v) -> String\n\n説明。\n\n" \
             "`````\nline1\n`````\n`````\n# => result\n`````\n  \n\n`````\nline2\n`````\n"
    assert_equal compile_method(@rd, rd_src), compile_method(@md, md_src),
      "md source:\n#{md_src}"
  end

  def test_leftover_emlist_in_doc
    # news/2_5_0 型: リスト脈絡の #@samplecode は md に生のまま残り、
    # 前処理で //emlist になる。RDCompiler と同じく独立ブロックとして描画する
    rd_src = "  * 項目 [[m:Coverage.start]]\n//emlist[][ruby]{\nCoverage.start\n//}\n  * 次の項目\n"
    md_src = "  - 項目 [m:Coverage.start]\n//emlist[][ruby]{\nCoverage.start\n//}\n  - 次の項目\n"
    assert_equal @rd.compile(rd_src), @md.compile(md_src), "md source:\n#{md_src}"
  end

  def test_leftover_emlist_in_method_entry
    rd_src = "--- m(v) -> String\n\n説明。\n//emlist[][ruby]{\np 1\n//}\n"
    md_src = "### def m(v) -> String\n\n説明。\n//emlist[][ruby]{\np 1\n//}\n"
    assert_equal compile_method(@rd, rd_src), compile_method(@md, md_src),
      "md source:\n#{md_src}"
  end

  def test_doc_see_renders_see_also
    # findings#1: doc/lib ページの @see も SEE_ALSO として解釈する
    # （従来は RDCompiler の library_file に分岐がなく段落テキストだった）
    rd_src = "= 見出し\n\n説明。\n\n@see [[m:Array#each]]\n"
    md_src = BitClust::RRDToMarkdown.convert(rd_src)
    rd_html = @rd.compile(rd_src)
    assert_match(/\[SEE_ALSO\]/, rd_html)
    assert_equal rd_html, @md.compile(md_src), "md source:\n#{md_src}"
  end

  def test_entry_paragraph_with_midline_see_not_swallowed
    # findings#3: 行頭アンカー無しの /@see/ dispatch が本文行を see() に
    # 吸う潜在バグ。段落の先頭行に「@see」を含む文があっても段落のまま
    rd_src = "--- m(v) -> String\n\n本文中で @see を説明する行。\n"
    html = compile_method(@rd, rd_src)
    assert_not_match(/SEE_ALSO/, html)
    assert_match(/本文中で @see を説明する行。/, html)
  end

  def test_undef_renders_dedicated_message
    # {: undef} 属性行は専用の説明文を描画する（statichtml は undefined を
    # skip するため露出は server 等の動的経路のみ）
    rd_src = "--- <(other) -> bool\n{: undef}\n"
    md_src = BitClust::RRDToMarkdown.convert(rd_src)
    rd_html = compile_method(@rd, rd_src)
    assert_not_match(/UNKNOWN_META_INFO/, rd_html)
    assert_match(/このメソッドは定義されていません/, rd_html)
    assert_equal rd_html, compile_method(@md, md_src), "md source:\n#{md_src}"
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
    # Complex#< 型: {: undef} 属性行。両経路とも「定義されていません」を描画
    assert_equivalent_method <<~RD
      --- <(other)    -> bool
      {: undef}
    RD
  end

  def test_nomethod_metadata
    # @nomethod（説明のための未定義メソッド）はマーカーなので本文には描画しない
    md_src = BitClust::RRDToMarkdown.convert(<<~RD)
      --- to_a -> Array
      {: nomethod}

      説明のためここに記載しています。
    RD
    html = compile_method(@md, md_src)
    assert_not_include(html, 'UNKNOWN_META_INFO')
    assert_not_include(html, '{:')
    assert_include(html, '説明のためここに記載しています。')
  end

  def test_nomethod_metadata_equivalence
    assert_equivalent_method <<~RD
      --- to_a -> Array
      {: nomethod}

      説明のためここに記載しています。
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
    # String#% 型: dd は「インデント段落 + emlist」を交互に何個でも受ける。
    # 1つ目の継続（プレフィックスを…）は dt の直後（空行なし）なので
    # lazy continuation としてインデント1でも dd に入るが、2つ目
    # （浮動小数点数…）は emlist の後の空行を挟むため、CommonMark 準拠の
    # ためマーカー幅(2)と同じインデントにしている（#3232 対応）
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

  # ---- M2: GFM モード（:gfm オプション） ----
  # M1 等価モード（既定）と違い、RDCompiler と同一 HTML ではなく
  # GFM の表現（<code>/<strong>/<table>）を描画する

  def gfm_compiler
    BitClust::MDCompiler.new(@u, 1, { :database => @db, :gfm => true })
  end

  def test_gfm_code_span_in_paragraph
    html = gfm_compiler.compile("# タイトル\n\nこの `code` はスパンです。\n")
    assert_include html, "この <code>code</code> はスパンです。"
  end

  def test_gfm_escaped_backtick_stays_literal
    html = gfm_compiler.compile("# タイトル\n\n\\`--version' と \\`-' の話。\n")
    assert_include html, "`--version' と `-' の話。"
    assert_not_include html, "<code>"
  end

  def test_gfm_auto_span_becomes_code
    html = gfm_compiler.compile("# タイトル\n\n`__FILE__` を返します。\n")
    assert_include html, "<code>__FILE__</code> を返します。"
  end

  def test_gfm_code_span_escapes_html
    html = gfm_compiler.compile("# タイトル\n\n`a<b>` です。\n")
    assert_include html, "<code>a&lt;b&gt;</code> です。"
  end

  # ---- CommonMark 6.1: N 連バッククォートのコードスパン(doctree#3232) ----

  def test_gfm_double_backtick_span_contains_single_backtick
    # 開始と同じ長さ(2連)のバッククォート列で閉じ、前後の空白を1個ずつ剥ぐ
    html = gfm_compiler.compile("# T\n\n`` foo ` bar `` です。\n")
    assert_include html, "<code>foo ` bar</code> です。"
  end

  def test_gfm_triple_backtick_span
    # 行頭 ``` はブロックレベルのフェンスと解釈されるため、文中に置く
    html = gfm_compiler.compile("# T\n\n見よ ``` code ``` です。\n")
    assert_include html, "<code>code</code> です。"
  end

  def test_gfm_unbalanced_backtick_run_stays_literal
    # 閉じる相手のいない開始列はコードスパンにせずリテラルのまま
    html = gfm_compiler.compile("# T\n\n``foo` です。\n")
    assert_include html, "``foo` です。"
    assert_not_include html, "<code>"
  end

  def test_gfm_escaped_backtick_inside_span_keeps_backslash
    # コードスパン内ではバックスラッシュエスケープが無効(CommonMark 6.1)。
    # \` はバックスラッシュごとリテラルに残る(GitHub の実描画と同一)
    html = gfm_compiler.compile("# T\n\n`` \\` `` は変換されません。\n")
    assert_include html, "<code>\\`</code> は変換されません。"
  end

  def test_gfm_bare_backtick_in_bracket_ref_still_resolves
    # 既存の [m:$`](素のバッククォート)の後方互換
    html = gfm_compiler.compile("# T\n\n[m:$`] を参照。\n")
    assert_include html, ">$`</a>"
    assert_not_include html, "[[m:$"
  end

  def test_gfm_escaped_backtick_in_bracket_ref_resolves
    # znz さん提示の書き方(doctree#3232 レビュー): [m:$\`] は
    # [m:$`](素のバッククォート)と同じ参照へ解決される
    escaped = gfm_compiler.compile("# T\n\n[m:$\\`] を参照。\n")
    bare = gfm_compiler.compile("# T\n\n[m:$`] を参照。\n")
    assert_equal bare, escaped
    assert_include escaped, ">$`</a>"
    assert_not_include escaped, "[[m:$"
    assert_not_include escaped, "\\`"
  end

  def test_gfm_znz_gsub_paragraph_golden
    # doctree PR #3232 レビューで znz さんが提示した段落そのもの
    # (String#gsub の説明)。GitHub 上の実描画(gh api -X POST /markdown で
    # 確認済み)と同等の構造 — \`・\'・\+ がコードスパンに、
    # 3つの参照がすべて解決されること — をまとめて確認する
    md = <<~MD
      # T

      置換文字列内では `` \\` ``、`\\'`、`\\+` も使えます。
      これらは [m:$\\`]、[m:$']、[m:$+] に対応します。
    MD
    html = gfm_compiler.compile(md)
    assert_include html, "<code>\\`</code>"
    assert_include html, "<code>\\'</code>"
    assert_include html, "<code>\\+</code>"
    assert_include html, ">$`</a>"
    assert_include html, ">$'</a>"
    assert_include html, ">$+</a>"
    assert_not_include html, "[[m:$"
    assert_not_include html, "[m:$"
  end

  def test_gfm_ref_and_span_coexist
    html = gfm_compiler.compile("# タイトル\n\n[c:String] と `x` を参照。\n")
    assert_include html, "</a> と <code>x</code> を参照。"
  end

  def test_gfm_strong_number
    html = gfm_compiler.compile("# タイトル\n\n**1.** 最初の説明。\n")
    assert_include html, "<strong>1.</strong> 最初の説明。"
  end

  def test_gfm_param_name_code
    md = "### def m(v) -> String\n\n説明。\n\n- **param** `v` -- 値。\n"
    html = compile_method(gfm_compiler, md)
    assert_include html, "[PARAM] <code>v</code>:"
  end

  def test_gfm_raise_name_code
    md = "### def m(v) -> String\n\n説明。\n\n- **raise** `TypeError` -- 型エラー。\n"
    html = compile_method(gfm_compiler, md)
    assert_include html, "[EXCEPTION] <code>TypeError</code>:"
  end

  def test_gfm_dlist_code_term
    html = gfm_compiler.compile("# タイトル\n\n- **`type`**: Content-Type ヘッダ。\n")
    assert_include html, "<dt><code>type</code></dt>"
  end

  def test_gfm_dlist_ref_term_resolves_inside_code
    # spec/eval 型: ref のコード term は <code> 内でリンク解決する
    html = gfm_compiler.compile("# T\n\n- **`[c:String]`**: 文字列クラス。\n")
    assert_include html, "<dt><code><a href="
    assert_include html, "</a></code></dt>"
  end

  def test_gfm_dlist_term_inner_stripped
    # news/1.8.2 型: スパン内の末尾スペースは dt に含めない（rd の strip と同じ）
    html = gfm_compiler.compile("# T\n\n- **`CSV.open, and generate `**: 説明。\n")
    assert_include html, "<dt><code>CSV.open, and generate</code></dt>"
  end

  def test_gfm_dlist_plain_term_stays_plain
    html = gfm_compiler.compile("# タイトル\n\n- **用語**: 説明文。\n")
    assert_include html, "<dt>用語</dt>"
  end

  def test_gfm_table_basic
    md = <<~MD
      # タイトル

      | 文字列 | ステータス |
      |--------|-----------|
      | `"OK"` | 200 |
    MD
    html = gfm_compiler.compile(md)
    assert_include html, "<table>"
    assert_include html, "<th>文字列</th>"
    assert_include html, "<td><code>&quot;OK&quot;</code></td>"
    assert_include html, "<td>200</td>"
  end

  def test_gfm_table_alignment
    md = "# T\n\n| a | b | c |\n|:--|:-:|--:|\n| 1 | 2 | 3 |\n"
    html = gfm_compiler.compile(md)
    assert_include html, '<th align="left">a</th>'
    assert_include html, '<th align="center">b</th>'
    assert_include html, '<th align="right">c</th>'
    assert_include html, '<td align="right">3</td>'
  end

  def test_gfm_pipe_line_without_delimiter_is_paragraph
    # FalseClass 型: | 演算子の散文はテーブルにしない（区切り行必須）
    md = "# T\n\n| は再定義可能な演算子です。通常は false | other の形で使われます。\n"
    html = gfm_compiler.compile(md)
    assert_not_include html, "<table>"
    assert_include html, "| は再定義可能な演算子です。"
  end

  def test_gfm_off_by_default
    html = @md.compile("# タイトル\n\nこの `code' はどうか。\n")
    assert_not_include html, "<code>code"
  end

  # ---- M2: Markdown リンク（MARKUP_SPEC §7.4/§7.5、news/1_9_0 型） ----

  def test_gfm_autolink
    html = gfm_compiler.compile("# T\n\n<https://example.com/a#b> を参照。\n")
    assert_include html,
      '<a class="external" href="https://example.com/a#b">https://example.com/a#b</a> を参照。'
  end

  def test_gfm_autolink_in_dlist_description
    md = "# T\n\n- **`__callee__`**:\n\n  <https://example.com/x>\n"
    html = gfm_compiler.compile(md)
    assert_include html, '<a class="external" href="https://example.com/x">https://example.com/x</a>'
  end

  def test_gfm_autolink_requires_url_scheme
    html = gfm_compiler.compile("# T\n\na <b> c です。\n")
    assert_include html, "a &lt;b&gt; c です。"
    assert_not_include html, "<a "
  end

  def test_gfm_inline_link
    html = gfm_compiler.compile("# T\n\n[例示ドメイン](https://example.com)のサポート\n")
    assert_include html, '<a class="external" href="https://example.com">例示ドメイン</a>のサポート'
  end

  def test_gfm_inline_link_with_bracketed_text
    # news/1_9_0 型: [[ruby-cvs:16833]](アーカイブURL) — 表示テキストに角括弧
    html = gfm_compiler.compile("# T\n\n[[ruby-cvs:16833]](https://example.com/16833)\n")
    assert_include html, '<a class="external" href="https://example.com/16833">[ruby-cvs:16833]</a>'
  end

  def test_gfm_inline_link_text_with_parens_and_url_query
    md = "# T\n\n[patch: activity in 1.9 (2006-06)](https://example.com/hiki.rb?Changes+in+Ruby)\n"
    html = gfm_compiler.compile(md)
    assert_include html,
      '<a class="external" href="https://example.com/hiki.rb?Changes+in+Ruby">patch: activity in 1.9 (2006-06)</a>'
  end

  def test_gfm_fragment_link
    html = gfm_compiler.compile("# T\n\n[破壊的な変更](#mutable) を参照。\n")
    assert_include html, '<a href="#mutable">破壊的な変更</a> を参照。'
  end

  def test_gfm_non_url_destination_stays_text
    # 参照直後の括弧書きをリンクと誤認しない（宛先は URL/#フラグメントのみ）
    html = gfm_compiler.compile("# T\n\n[c:String](文字列)を参照。\n")
    assert_include html, "</a>(文字列)を参照。"
  end

  def test_gfm_link_inside_code_span_stays_code
    html = gfm_compiler.compile("# T\n\n`[x](https://example.com)` はコード。\n")
    assert_include html, "<code>[x](https://example.com)</code> はコード。"
  end

  def test_gfm_link_escapes_html_in_text_and_url
    html = gfm_compiler.compile("# T\n\n[a<b>](https://example.com/?q=<x>)\n")
    assert_include html, '<a class="external" href="https://example.com/?q=&lt;x&gt;">a&lt;b&gt;</a>'
  end

  # ---- M2: インデントされたコードフェンス（リスト・dlist 内、news/1_9_0 型） ----

  def test_gfm_indented_fence_in_dlist_description
    md = <<~MD
      # T

      - **`Dir.glob`**:

        説明文です。

        ```ruby
        p Dir.glob(["f*","b*"])  # => ["foo", "bar"]
        ```

        続きの説明。
    MD
    html = gfm_compiler.compile(md)
    assert_include html, '<pre class="highlight ruby">'
    assert_include html, 'Dir.glob'
    assert_not_include html, '```'
    # 内容はフェンス行のインデント分がデデントされる
    assert_include html, "<span class=\"nb\">p</span>"
    assert_include html, "<p>\n続きの説明。\n</p>"
  end

  def test_gfm_indented_fence_without_lang
    md = "# T\n\n- **`proc`**:\n\n  説明。\n\n  ```text\n  x = {|a| p a}\n  ```\n"
    html = gfm_compiler.compile(md)
    assert_include html, "x = {|a| p a}"
    assert_not_include html, '```'
  end

  def test_gfm_indented_fence_in_list_item
    md = "# T\n\n- 項目\n  ```ruby\n  p 1\n  ```\n- 次の項目\n"
    html = gfm_compiler.compile(md)
    assert_include html, '<pre class="highlight ruby">'
    assert_include html, "次の項目"
    assert_not_include html, '```'
  end

  def test_gfm_indented_fence_at_top_level
    # リスト項目と空行で切り離されたフェンス（行駆動モデルではトップレベル扱い）
    md = "# T\n\n- 項目\n\n  ```ruby\n  p 1\n  ```\n\n本文。\n"
    html = gfm_compiler.compile(md)
    assert_include html, '<pre class="highlight ruby">'
    assert_include html, "本文。"
    assert_not_include html, '```'
  end

  def test_gfm_indented_fence_in_method_entry
    md = "### def m(v) -> String\n\n説明。\n\n- **`opt`**:\n\n  ```ruby\n  p 1\n  ```\n"
    html = compile_method(gfm_compiler, md)
    assert_include html, '<pre class="highlight ruby">'
    assert_not_include html, '```'
  end

  def test_gfm_indented_fence_in_param_continuation
    md = "### def m(v) -> String\n\n説明。\n\n- **param** `v` -- 値。\n\n  ```ruby\n  p 1\n  ```\n"
    html = compile_method(gfm_compiler, md)
    assert_include html, '<pre class="highlight ruby">'
    assert_not_include html, '```'
  end

  def test_gfm_stray_indented_line_does_not_hang
    # リストと空行で切り離された残余のインデント行はどのブロックにも
    # 該当しない。段落として消費する（従来はディスパッチが進まずハング）
    md = "# T\n\n- 項目\n\n  切り離された継続行。\n\n本文。\n"
    html = gfm_compiler.compile(md)
    assert_include html, "切り離された継続行。"
    assert_include html, "本文。"
  end

  def test_gfm_stray_indented_line_in_method_entry_does_not_hang
    md = "### def m(v) -> String\n\n- 項目\n\n  切り離された継続行。\n"
    html = compile_method(gfm_compiler, md)
    assert_include html, "切り離された継続行。"
  end

  def test_gfm_indented_fence_with_title
    md = "# T\n\n- 項目\n  ```ruby title=\"例\"\n  p 1\n  ```\n"
    html = gfm_compiler.compile(md)
    assert_include html, '<span class="caption">例</span>'
    assert_include html, '<pre class="highlight ruby">'
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

  # ---- CommonMark 準拠のリスト継続インデント (doctree#3232, znz レビュー) ----
  # https://spec.commonmark.org/0.31.2/#list-items Example 255-258, 264 相当。
  # マーカーの内容カラム幅（「- 」なら2、dlist の dt も常に「- 」なので2）
  # 未満のインデントは、空行を挿むと項目に属さない。ただし空行を挿まない
  # 直接継続（lazy continuation）は CommonMark 同様、幅を問わず許容する。

  def test_dlist_direct_continuation_allows_shallow_indent
    # 空行なしの直接継続（lazy）はマーカー幅(2)未満でも dd に含まれる
    # （symref.md の実例の大半はこの形）
    html = @md.compile("- **term**:\n description.\n")
    assert_match(%r{<dd>\s*<p>\s*description\.\s*</p>\s*</dd>}m, html)
  end

  def test_dlist_blank_continuation_with_marker_width_indent_stays_in_dd
    # CommonMark Example 256 相当: マーカー幅(2)以上のインデントなら
    # 空行を挟んだ2段落目も dd に含まれる
    html = @md.compile("- **term**:\n  one\n\n  two\n")
    assert_include(html, 'one')
    assert_include(html, 'two')
    assert_operator(html.index('two'), :<, html.index('</dd>'))
  end

  def test_dlist_blank_continuation_with_shallow_indent_breaks_out
    # CommonMark Example 255 相当（symref.md の実例と同型）:
    # 空行を挟んだ1スペースだけの継続はマーカー幅(2)未満のため dd に
    # 属さず、dl の外のトップレベル段落になる
    html = @md.compile("- **`2 + 3`**:\n\n 足し算です。\n")
    assert_operator(html.index('</dd>'), :<, html.index('足し算'))
    assert_operator(html.index('</dl>'), :<, html.index('足し算'))
  end

  def test_dlist_multiple_blank_lines_between_paragraphs
    # CommonMark Example 262 相当: 2行以上の空行を挟んでも
    # インデントが十分なら dd の続きとして扱う
    html = @md.compile("- **term**:\n  one\n\n\n  two\n")
    assert_operator(html.index('two'), :<, html.index('</dd>'))
  end

  def test_dlist_fence_after_blank_requires_marker_width
    # フェンスは lazy continuation できない（空行の有無に関わらず
    # マーカー幅以上のインデントが必要）。幅未満なら dd の外の
    # トップレベルフェンスになる
    html = @md.compile("- **term**:\n\n ```\n code\n ```\n")
    assert_operator(html.index('</dd>'), :<, html.index('<pre>'))
  end

  def test_item_list_blank_continuation_with_sufficient_indent_stays_nested
    # CommonMark Example 256 相当・doctree news/*.md の実例型:
    # 現行実装は空行に当たった時点で項目の外に「脱走」していたが、
    # マーカー幅以上のインデントなら項目（li）の中に留まる
    html = @md.compile("- one\n\n  two\n")
    assert_operator(html.index('two'), :<, html.index('</li>'))
  end

  def test_item_list_blank_continuation_with_insufficient_indent_breaks_out
    # CommonMark Example 255 相当: マーカー幅未満なら項目の外になる
    html = @md.compile("- one\n\n two\n")
    assert_operator(html.index('</li>'), :<, html.index('two'))
  end

  def test_item_list_fence_after_blank_with_sufficient_indent_stays_nested
    # news/2_7_0.md 等の実例型:「- 説明文\n\n    ```ruby\n...\n    ```」の
    # ようにフェンス例が項目に属したまま描画される（従来は脱走していた）
    html = @md.compile("- one\n\n  ```ruby\n  code\n  ```\n")
    assert_operator(html.index('<pre'), :<, html.index('</li>'))
  end

  def test_item_list_shallow_direct_continuation_still_works
    # news/2_6_0 型（既存の RD 由来コンテンツ）: 空行なしの直接継続は
    # 項目マーカーより浅いインデントでも項目の継続のまま（回帰確認）
    assert_equivalent_doc <<~RD
      = タイトル

        * 項目の一行目が長くて
       折り返した継続行。

      本文。
    RD
  end

  def test_ordered_item_list_blank_continuation_requires_marker_width
    # 番号付きリストはマーカー文字列の幅がマーカーごとに変わる
    # （「1. 」なら3）。幅未満は空行を挟むと項目の外になる
    html = @md.compile("1. one\n\n  two\n")
    assert_operator(html.index('</li>'), :<, html.index('two'))
    wide = @md.compile("1. one\n\n   two\n")
    assert_operator(wide.index('two'), :<, wide.index('</li>'))
  end

  # ---- インデントコードブロックの検知・警告 (CommonMark Example 264 相当) ----
  # 言語指定を推奨するため実装は非対応のまま。互換性を壊さず、検知したら
  # stderr に警告のみ出す

  def test_warns_on_top_level_indented_code_block
    err = capture_stderr { @md.compile("説明。\n\n    code like text\n") }
    assert_match(/warning/i, err)
    assert_match(/:\d+/, err) # ファイル名(または識別子):行番号
    # 描画そのものは変更しない(非互換のまま、警告のみ)
    html = @md.compile("説明。\n\n    code like text\n")
    assert_match(%r{<p>\s*code like text\s*</p>}m, html)
    assert_not_match(/<pre>/, html)
  end

  def test_no_warning_for_shallow_indent_paragraph
    err = capture_stderr { @md.compile("説明。\n\n  two spaces only\n") }
    assert_equal('', err)
  end

  def test_no_warning_for_indented_content_consumed_by_list_item
    # リストの中に正しく取り込まれるインデントは警告対象外
    # （リスト外・フェンス外のみが対象）
    err = capture_stderr { @md.compile("- one\n\n      four space continuation\n") }
    assert_equal('', err)
  end

  def test_no_warning_for_fenced_code_block
    err = capture_stderr { @md.compile("```ruby\n    x = 1\n```\n") }
    assert_equal('', err)
  end

  def test_md_ref_module_function_display_typemark
    # bitclust#282: Markdown ソースの [m:Kernel?.at_exit] は inline 復元時に
    # ".#" へ正規化される(RRD の MethodSpec 互換)が、表示ラベルは DB
    # バージョンが 4.0 以降なら "?." に戻す。3.4 以前は ".#" のまま。
    # どちらの表記で書かれていても、ページの見出し表記と常に一致する
    src = "### def m(v) -> String\n\n" \
          "[m:Kernel?.at_exit] と [m:Kernel.#at_exit] を参照。\n"
    { '3.4' => 'Kernel.#at_exit', '4.0' => 'Kernel?.at_exit' }.each do |version, label|
      db = BitClust::MethodDatabase.dummy("version" => version)
      md = BitClust::MDCompiler.new(@u, 1, { :database => db })
      html = compile_method(md, src)
      assert_equal(2, html.scan(">#{label}</a>").size,
                   "version=#{version}\n#{html}")
    end
  end

end

# lang 指定付きコードブロックのハイライト（ruby は Ripper ベースの
# SyntaxHighlighter、その他の言語は Rouge、未知の言語はエスケープのみ）
class TestMDCompilerRougeHighlight < Test::Unit::TestCase
  def setup
    @dummy = 'dummy'
    @u = BitClust::URLMapper.new(Hash.new { @dummy })
    @db = BitClust::MethodDatabase.dummy("version" => "2.0.0")
    @md = BitClust::MDCompiler.new(@u, 1, { :database => @db, :gfm => true })
    @rd = BitClust::RDCompiler.new(@u, 1, { :database => @db })
  end

  def test_c_fence_is_highlighted_with_rouge
    html = @md.compile("```c\nint x = 1; /* comment */\n```\n")
    assert_match(/<pre class="highlight c">/, html)
    assert_match(%r{<span class="kt">int</span>}, html)
    assert_match(%r{<span class="cm">/\* comment \*/</span>}, html)
  end

  def test_ruby_alias_rb_uses_bitclust_highlighter
    ruby_html = @md.compile("```ruby\nputs 1\n```\n")
    rb_html = @md.compile("```rb\nputs 1\n```\n")
    assert_equal(ruby_html.sub('highlight ruby', 'highlight rb'), rb_html)
    # bitclust の SyntaxHighlighter 由来のマークアップ（Rouge の Ruby lexer ではなく）
    assert_match(%r{<span class="nb">puts</span>}, rb_html)
  end

  def test_unknown_lang_fence_is_escaped
    html = @md.compile("```nosuchlang\n<b>&raw</b>\n```\n")
    assert_match(/<pre class="highlight nosuchlang">/, html)
    assert_match(/&lt;b&gt;&amp;raw&lt;\/b&gt;/, html)
    assert_not_match(/<b>/, html)
  end

  def test_text_fence_is_escaped_without_highlight
    html = @md.compile("```text\n<b>plain</b>\n```\n")
    assert_match(/&lt;b&gt;plain&lt;\/b&gt;/, html)
    assert_not_match(/<b>plain/, html)
  end

  # info string パースの直接テスト。ハイライト出力経由の検証は Ruby の
  # パーサ版差(同じ断片でもエラー報告の有無が変わる)で不具合がマスク
  # されうるため、返り値そのものを固定する
  class BitClust::MDCompiler; public :parse_fence_info; end
  data("lang のみ"       => ["ruby", ["ruby", nil, false]],
       "invalid 付き"    => ["ruby invalid", ["ruby", nil, true]],
       "title 付き"      => ['ruby title="例"', ["ruby", "例", false]],
       "invalid + title" => ['ruby invalid title="SyntaxError の例"',
                             ["ruby", "SyntaxError の例", true]],
       "title 内エスケープ + invalid" => ['ruby invalid title="a\"b"',
                             ["ruby", 'a"b', true]],
       "未知の余分な語"  => ["ruby foo", [nil, nil, false]],
       "空"              => ["", [nil, nil, false]])
  def test_parse_fence_info(data)
    rest, expected = data
    assert_equal(expected, @md.parse_fence_info(rest))
  end

  # ```ruby invalid: 構文として完全でないコード(SyntaxError の例・文法断片)を
  # Ripper の構文チェックなしで Rouge の Ruby lexer により色付けする(issue #251)
  def test_ruby_invalid_fence_uses_rouge_without_syntax_check
    # Ripper ではパースできない断片でもビルドエラーにならない
    html = @md.compile("```ruby invalid\nif cond then\n```\n")
    assert_match(/<pre class="highlight ruby">/, html)
    assert_match(%r{<span class="k">if</span>}, html)
  end

  def test_ruby_invalid_fence_with_title
    html = @md.compile("```ruby invalid title=\"SyntaxError の例\"\ndef broken(\n```\n")
    assert_match(%r{<span class="caption">SyntaxError の例</span>}, html)
    assert_match(/<pre class="highlight ruby">/, html)
    assert_match(%r{<span class="k">def</span>}, html)
  end

  def test_invalid_flag_on_other_lang_is_harmless
    plain = @md.compile("```c\nint x = 1;\n```\n")
    flagged = @md.compile("```c invalid\nint x = 1;\n```\n")
    assert_equal(plain, flagged)
  end

  def test_ruby_fence_without_invalid_still_checks_syntax
    md = BitClust::MDCompiler.new(@u, 1,
      { :database => @db, :gfm => true, :stop_on_syntax_error => false })
    html = md.compile("```ruby\nif cond then\n```\n")
    # invalid なしの ruby は従来どおり構文チェックされ、エラー時は
    # エスケープのみのフォールバック(色付けなし)になる
    assert_not_match(/<span class="k">/, html)
    assert_match(/if cond then/, html)
  end

  def test_rd_emlist_with_c_lang_is_equivalent
    rd_src = "//emlist[キャプション][c]{\nint x = 1;\n//}\n"
    md_src = BitClust::RRDToMarkdown.convert(rd_src)
    assert_equal(@rd.compile(rd_src), @md.compile(md_src), "md source:\n#{md_src}")
    assert_match(%r{<span class="kt">int</span>}, @rd.compile(rd_src))
  end

end

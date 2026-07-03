# frozen_string_literal: true

require 'test/unit'

require 'bitclust/rrd_to_markdown'

class TestRRDToMarkdown < Test::Unit::TestCase
  def convert(rrd)
    BitClust::RRDToMarkdown.convert(rrd)
  end

  # Step 1: H1 ヘッダとパススルー

  def test_module_header
    assert_equal "# module Comparable\n",
      convert("= module Comparable\n")
  end

  def test_class_header_with_superclass
    assert_equal "# class Array < Object\n",
      convert("= class Array < Object\n")
  end

  def test_reopen_header
    assert_equal "# reopen Kernel\n",
      convert("= reopen Kernel\n")
  end

  def test_text_passthrough
    rrd = "= module Comparable\n\n説明文。\n"
    expected = "# module Comparable\n\n説明文。\n"
    assert_equal expected, convert(rrd)
  end

  def test_directive_passthrough
    rrd = "= module Comparable\n\n\#@since 2.4.0\ntext\n\#@end\n"
    expected = "# module Comparable\n\n\#@since 2.4.0\ntext\n\#@end\n"
    assert_equal expected, convert(rrd)
  end

  def test_comment_passthrough
    assert_equal "\#@# これはコメント\n",
      convert("\#@# これはコメント\n")
  end

  def test_include_passthrough
    assert_equal "\#@include(io/buffer.md)\n",
      convert("\#@include(io/buffer.md)\n")
  end

  # Step 2: H2 セクションヘッダ

  def test_h2_instance_methods
    assert_equal "## Instance Methods\n",
      convert("== Instance Methods\n")
  end

  def test_h2_class_methods
    assert_equal "## Class Methods\n",
      convert("== Class Methods\n")
  end

  def test_h2_constants
    assert_equal "## Constants\n",
      convert("== Constants\n")
  end

  # Step 3: メソッドシグネチャ + コードブロック

  def test_instance_method_signature
    # B1: 空白を保持（正規化しない）
    assert_equal "### def ==(other)    -> bool\n",
      convert("--- ==(other)    -> bool\n")
  end

  def test_method_signature_whitespace_preserved
    assert_equal "### def [](nth)    -> object | nil\n",
      convert("--- [](nth)    -> object | nil\n")
  end

  def test_method_signature_with_block
    assert_equal "### def new(size) {|index| ... }    -> Array\n",
      convert("--- new(size) {|index| ... }    -> Array\n")
  end

  def test_multiple_signatures
    rrd = "--- [](nth) -> object | nil\n--- at(nth) -> object | nil\n"
    expected = "### def [](nth) -> object | nil\n### def at(nth) -> object | nil\n"
    assert_equal expected, convert(rrd)
  end

  def test_code_block_with_label
    rrd = "\#@samplecode 例\n1 == 1   # => true\n\#@end\n"
    expected = "```ruby title=\"例\"\n1 == 1   # => true\n```\n"
    assert_equal expected, convert(rrd)
  end

  def test_code_block_without_label
    rrd = "\#@samplecode\n1 == 1\n\#@end\n"
    expected = "```ruby\n1 == 1\n```\n"
    assert_equal expected, convert(rrd)
  end

  def test_samplecode_label_with_backslash
    rrd = "\#@samplecode \"\\n\" を含む例\n1\n\#@end\n"
    expected = "```ruby title=\"\\\"\\\\n\\\" を含む例\"\n1\n```\n"
    assert_equal expected, convert(rrd)
  end

  def test_emlist_with_caption_and_lang
    rrd = "//emlist[例][ruby]{\nputs 'hello'\n//}\n"
    expected = "```ruby title=\"例\"\nputs 'hello'\n```\n"
    assert_equal expected, convert(rrd)
  end

  def test_emlist_without_caption_with_lang
    rrd = "//emlist[][sh]{\necho hello\n//}\n"
    expected = "```sh\necho hello\n```\n"
    assert_equal expected, convert(rrd)
  end

  def test_emlist_without_caption_without_lang
    rrd = "//emlist{\nplain text\n//}\n"
    expected = "```\nplain text\n```\n"
    assert_equal expected, convert(rrd)
  end

  def test_emlist_caption_with_double_quote
    rrd = "//emlist[He said \"hello\"][ruby]{\ncode\n//}\n"
    expected = "```ruby title=\"He said \\\"hello\\\"\"\ncode\n```\n"
    assert_equal expected, convert(rrd)
  end

  # Step 4: ClassName. → self. 変換

  def test_class_method_keeps_classname
    rrd = "= class Array < Object\n\n--- Array.try_convert(obj) -> Array | nil\n"
    result = convert(rrd)
    assert_match(/### def Array\.try_convert\(obj\)/, result)
  end

  def test_module_method_keeps_classname
    rrd = "= module Benchmark\n\n--- Benchmark.measure(label) -> Benchmark::Tms\n"
    result = convert(rrd)
    assert_match(/### def Benchmark\.measure\(label\)/, result)
  end

  # Step 5: 定数・グローバル変数

  def test_constant_signature
    assert_equal "### const CR -> String\n",
      convert("--- CR -> String\n")
  end

  def test_constant_without_arrow
    assert_equal "### const START\n",
      convert("--- START\n")
  end

  def test_global_variable_signature
    assert_equal "### gvar $DEBUG -> bool\n",
      convert("--- $DEBUG -> bool\n")
  end

  # module_function

  def test_module_function_signature
    rrd = "== Module Functions\n\n--- measure(label) -> Benchmark::Tms\n"
    result = convert(rrd)
    assert_match(/### module_function def measure\(label\)/, result)
  end

  # ClassName.method はそのまま保持（返り値なしパターン）

  def test_class_method_keeps_classname_without_nil
    rrd = "= class Array < Object\n\n--- Array.try_convert(obj) -> Array\n"
    result = convert(rrd)
    assert_match(/### def Array\.try_convert\(obj\)/, result)
  end

  # 大文字始まりメソッド（( がある）

  def test_uppercase_method_with_parens
    assert_equal "### def DEBUG=(val)\n",
      convert("--- DEBUG=(val)\n")
  end

  # .# → ? 参照変換

  def test_module_function_ref
    assert_equal "テスト [m:Kernel?.open]\n",
      convert("テスト [[m:Kernel.#open]]\n")
  end

  # Step 6: @param / @return / @raise

  def test_param
    assert_equal "- **param** `other` -- 自身と比較したいオブジェクトを指定します。\n",
      convert("@param other 自身と比較したいオブジェクトを指定します。\n")
  end

  def test_raise
    assert_equal "- **raise** `ArgumentError` -- <=> が nil を返したときに発生します。\n",
      convert("@raise ArgumentError <=> が nil を返したときに発生します。\n")
  end

  def test_return
    assert_equal "- **return** -- 説明\n",
      convert("@return 説明\n")
  end

  def test_param_with_inline_ref
    assert_equal "- **param** `obj` -- [c:Range] オブジェクト\n",
      convert("@param obj [[c:Range]] オブジェクト\n")
  end

  def test_raise_with_inline_ref
    assert_equal "- **raise** `TypeError` -- [c:String] 以外\n",
      convert("@raise TypeError [[c:String]] 以外\n")
  end

  def test_return_with_inline_ref
    assert_equal "- **return** -- [c:Array] を返す\n",
      convert("@return [[c:Array]] を返す\n")
  end

  def test_return_alignment_spaces_preserved
    # B2: @return の整列空白を保持
    assert_equal "- **return** --      説明\n",
      convert("@return      説明\n")
  end

  def test_metadata_continuation_line
    rrd = "@raise ArgumentError self <=> min か、self <=> max が nil を返\n                     したときに発生します。\n"
    expected = "- **raise** `ArgumentError` -- self <=> min か、self <=> max が nil を返\n                     したときに発生します。\n"
    assert_equal expected, convert(rrd)
  end

  # Step 7: @see

  def test_see_single
    # B3: @see は [[→[ 置換のみ、区切りは保持
    assert_equal "- **SEE** [m:String#-@]\n",
      convert("@see [[m:String#-@]]\n")
  end

  def test_see_multiple_with_comma_space
    assert_equal "- **SEE** [m:A], [m:B]\n",
      convert("@see [[m:A]], [[m:B]]\n")
  end

  def test_see_multiple_without_comma_space
    # B3: カンマ後スペースなしも保持
    assert_equal "- **SEE** [m:A],[m:B]\n",
      convert("@see [[m:A]],[[m:B]]\n")
  end

  def test_see_class_ref
    assert_equal "- **SEE** [c:Array]\n",
      convert("@see [[c:Array]]\n")
  end

  def test_see_doc_ref
    assert_equal "- **SEE** [d:spec/m17n]\n",
      convert("@see [[d:spec/m17n]]\n")
  end

  # Step 8: YAML front matter

  def test_include_to_front_matter
    rrd = "= class Array < Object\ninclude Enumerable\n\n説明\n"
    expected = "---\ninclude:\n  - Enumerable\n---\n# class Array < Object\n\n説明\n"
    assert_equal expected, convert(rrd)
  end

  def test_multiple_includes_to_front_matter
    rrd = "= class Array < Object\ninclude Enumerable\ninclude Comparable\n\n説明\n"
    expected = "---\ninclude:\n  - Enumerable\n  - Comparable\n---\n# class Array < Object\n\n説明\n"
    assert_equal expected, convert(rrd)
  end

  def test_extend_to_front_matter
    rrd = "= class Foo < Object\nextend Forwardable\n"
    expected = "---\nextend:\n  - Forwardable\n---\n# class Foo < Object\n"
    assert_equal expected, convert(rrd)
  end

  def test_alias_to_front_matter
    rrd = "= class Integer < Numeric\nalias Fixnum\n"
    expected = "---\nalias:\n  - Fixnum\n---\n# class Integer < Numeric\n"
    assert_equal expected, convert(rrd)
  end

  def test_multi_entity_file_keeps_relations_in_body
    # 複数エンティティを含むファイルは帰属が曖昧なため front matter 化しない（分割前の安全策）
    rrd = "= object ARGF < ARGF.class\n\n説明1\n\n= class ARGF.class < Object\ninclude Enumerable\n\n説明2\n"
    result = convert(rrd)
    refute_match(/\A---/, result)
    assert_match(/# class ARGF\.class < Object\ninclude Enumerable/, result)
  end

  def test_versioned_alias_to_front_matter
    # 版条件（#@）で囲まれたヘッダ関係は front matter 内に #@ を挟んで表現する（§1.6）
    rrd = "= class Integer < Numeric\n\n\#@until 3.2\nalias Fixnum\nalias Bignum\n\#@end\n\n説明\n"
    expected = "---\nalias:\n\#@until 3.2\n  - Fixnum\n  - Bignum\n\#@end\n---\n# class Integer < Numeric\n\n説明\n"
    assert_equal expected, convert(rrd)
  end

  # Step 8.4: メタデータ領域の部分コミット
  # メタデータ（category/require/sublibrary）の後に版分岐つき散文や #@# コメントが
  # 続く場合、nest==0 の空行チェックポイントまでをメタデータとして確定し、
  # 残りは body に渡す（set.rd / thread.rd / rss.rd パターン）。

  def test_category_lifts_before_versioned_prose
    # set.rd: category Math + 空行 + 版分岐つき散文
    rrd = "category Math\n\n\#@since 3.0\n新しい説明\n\#@else\n古い説明\n\#@end\n\n本文。\n"
    expected = "---\ncategory: Math\n---\n" \
               "\#@since 3.0\n新しい説明\n\#@else\n古い説明\n\#@end\n\n本文。\n"
    assert_equal expected, convert(rrd)
  end

  def test_category_lifts_before_preprocessor_comment
    # rss.rd: category FileFormat + 空行 + #@# コメント
    rrd = "category FileFormat\n\n\#@# = rss\n\n説明。\n"
    expected = "---\ncategory: FileFormat\n---\n\#@# = rss\n\n説明。\n"
    assert_equal expected, convert(rrd)
  end

  def test_metadata_without_blank_checkpoint_stays_in_body
    # 空行チェックポイントが無い（category 直後にゲート）場合は従来どおり据え置き
    # （md→rd の再生成が category の後に空行を足すため、コミットすると一致しない）
    rrd = "category Math\n\#@since 3.0\n説明\n\#@end\n"
    assert_equal "category Math\n\#@since 3.0\n説明\n\#@end\n", convert(rrd)
  end

  # Step 8.5: extra front matter 注入（クロスファイル・オーケストレータ用）
  # library 所属・構造 since/until はファイル単体からは分からないため、
  # include グラフを解析したオーケストレータが注入する。

  def test_extra_front_matter_library
    rrd = "= class Bar < Object\n\n説明\n"
    expected = "---\nlibrary: foo\n---\n# class Bar < Object\n\n説明\n"
    assert_equal expected,
      BitClust::RRDToMarkdown.convert(rrd, extra_front_matter: { "library" => "foo" })
  end

  def test_extra_front_matter_ordering_with_collected_relations
    # §1.7 の順序: library → include/extend/alias → since/until
    rrd = "= class Bar < Object\ninclude Enumerable\n\n説明\n"
    expected = "---\nlibrary: foo\ninclude:\n  - Enumerable\nsince: \"3.2\"\n---\n" \
               "# class Bar < Object\n\n説明\n"
    assert_equal expected,
      BitClust::RRDToMarkdown.convert(rrd,
        extra_front_matter: { "library" => "foo", "since" => "3.2" })
  end

  def test_extra_front_matter_accepts_symbol_keys
    # IncludeGraph::Scope#gate は {since:, until:} のシンボルキーを返す
    rrd = "= class Bar < Object\n"
    expected = "---\nlibrary: foo\nuntil: \"4.0\"\n---\n# class Bar < Object\n"
    assert_equal expected,
      BitClust::RRDToMarkdown.convert(rrd,
        extra_front_matter: { library: "foo", until: "4.0" })
  end

  def test_extra_front_matter_on_multi_entity_file
    # library はファイル単位の情報なので、マルチエンティティでも曖昧なく注入できる
    # （ファイル内の全エンティティは同一ライブラリ所属。ヘッダ関係は body 据え置きのまま）
    rrd = "= object ARGF < ARGF.class\n\n説明1\n\n= class ARGF.class < Object\ninclude Enumerable\n\n説明2\n"
    result = BitClust::RRDToMarkdown.convert(rrd,
      extra_front_matter: { "library" => "_builtin" })
    assert result.start_with?("---\nlibrary: _builtin\n---\n"), result[0, 60].inspect
    assert_match(/include Enumerable/, result)
  end

  def test_extra_front_matter_rejects_unknown_keys
    assert_raise(ArgumentError) do
      BitClust::RRDToMarkdown.convert("= class Bar < Object\n",
        extra_front_matter: { "libary" => "typo" })
    end
  end

  def test_extra_front_matter_roundtrip_drops_injected_keys
    # 注入キーはオーケストレータ由来の横断情報なので、md→rd では body に現れず
    # 元の RRD がそのまま復元される
    require 'bitclust/markdown_to_rrd'
    rrd = "= class Bar < Object\ninclude Enumerable\n\n説明\n"
    md = BitClust::RRDToMarkdown.convert(rrd,
      extra_front_matter: { "library" => "foo", "since" => "3.2" })
    assert_equal rrd, BitClust::MarkdownToRRD.convert(md)
  end

  def test_versioned_include_if_to_front_matter
    rrd = "= class File < IO\n\#@if (version < \"1.8.0\")\ninclude File::Constants\n\#@end\n\n説明\n"
    expected = "---\ninclude:\n\#@if (version < \"1.8.0\")\n  - File::Constants\n\#@end\n---\n# class File < IO\n\n説明\n"
    assert_equal expected, convert(rrd)
  end

  def test_versioned_prose_not_treated_as_header_relation
    # #@ が本文（関係でない）を包む場合はヘッダ関係扱いしない
    rrd = "= module Foo\n\n\#@since 3.0\n本文\n\#@end\n"
    expected = "# module Foo\n\n\#@since 3.0\n本文\n\#@end\n"
    assert_equal expected, convert(rrd)
  end

  def test_front_matter_category
    rrd = "category Network\n\nライブラリの説明\n"
    result = convert(rrd)
    assert_match(/\A---\ncategory: Network\n---\n/, result)
    assert_match(/ライブラリの説明/, result)
  end

  def test_front_matter_require
    rrd = "require cgi/core\nrequire cgi/cookie\n\nライブラリの説明\n"
    result = convert(rrd)
    assert_match(/require:\n  - cgi\/core\n  - cgi\/cookie\n/, result)
  end

  def test_front_matter_sublibrary
    rrd = "sublibrary json/ext\n\nライブラリの説明\n"
    result = convert(rrd)
    assert_match(/sublibrary:\n  - json\/ext\n/, result)
  end

  def test_front_matter_category_and_require
    rrd = "category Network\n\nrequire socket\n\nライブラリの説明\n"
    result = convert(rrd)
    assert_match(/\A---\ncategory: Network\nrequire:\n  - socket\n---\n/, result)
  end

  def test_versioned_require_to_front_matter
    rrd = "category Network\n\n\#@since 1.9.1\nrequire cgi/core\nrequire cgi/cookie\n\#@end\n\n説明\n"
    expected = "---\ncategory: Network\nrequire:\n\#@since 1.9.1\n  - cgi/core\n  - cgi/cookie\n\#@end\n---\n説明\n"
    assert_equal expected, convert(rrd)
  end

  def test_file_spanning_version_gate_metadata_stays_in_body
    # ファイル全体を包む #@（構造的ゲート）はメタを front matter にしない（項目1で対応）
    rrd = "\#@since 1.9.1\n\ncategory Math\n\n説明\n\#@end\n"
    result = convert(rrd)
    refute_match(/\A---/, result)
    assert_match(/\A\#@since 1.9.1\n/, result)
  end

  def test_no_front_matter_when_no_metadata
    rrd = "= module Comparable\n\n説明\n"
    result = convert(rrd)
    assert_match(/\A# module Comparable\n/, result)
    refute_match(/\A---/, result)
  end

  def test_include_after_blank_line_to_front_matter
    rrd = "= class String < Object\n\ninclude Comparable\n\n説明\n"
    expected = "---\ninclude:\n  - Comparable\n---\n# class String < Object\n\n説明\n"
    assert_equal expected, convert(rrd)
  end

  # Step 9: アンカー付き見出し・H4

  def test_h3_with_anchor
    assert_equal "### 破壊的な変更 {#mutable}\n",
      convert("===[a:mutable] 破壊的な変更\n")
  end

  def test_h4_heading
    assert_equal "#### 小見出し\n",
      convert("==== 小見出し\n")
  end

  def test_h3_without_anchor
    assert_equal "### 読み込み\n",
      convert("=== 読み込み\n")
  end

  # Step 10: クロスリファレンス（インライン）

  def test_inline_class_ref
    assert_equal "[c:String] を参照。\n",
      convert("[[c:String]] を参照。\n")
  end

  def test_inline_method_ref
    assert_equal "[m:Array#each] と同じ。\n",
      convert("[[m:Array#each]] と同じ。\n")
  end

  def test_inline_multiple_refs
    assert_equal "[c:Array] と [c:Hash] を使う。\n",
      convert("[[c:Array]] と [[c:Hash]] を使う。\n")
  end

  def test_inline_bracket_method_ref
    # A2: [[m:Hash#[] ]] → [m:Hash#\[\]]
    assert_equal "- **SEE** [m:Hash#\\[\\]]\n",
      convert("@see [[m:Hash#[] ]]\n")
  end

  def test_inline_ref_with_trailing_bracket
    # [[m:Math::PI]]] → [m:Math::PI]]
    assert_equal "ら [-self, [m:Math::PI]] を返します。\n",
      convert("ら [-self, [[m:Math::PI]]] を返します。\n")
  end

  def test_inline_ref_not_in_code_block
    rrd = "\#@samplecode\n[[c:String]]\n\#@end\n"
    expected = "```ruby\n[[c:String]]\n```\n"
    assert_equal expected, convert(rrd)
  end

  # Step 11: リスト変換

  def test_unordered_list
    # B4: 元のインデント幅を保持
    rrd = " * item1\n * item2\n"
    expected = " - item1\n - item2\n"
    assert_equal expected, convert(rrd)
  end

  def test_unordered_list_2space_indent
    rrd = "  * item1\n  * item2\n"
    expected = "  - item1\n  - item2\n"
    assert_equal expected, convert(rrd)
  end

  def test_ordered_list
    rrd = " (1) 最初\n (2) 次\n (3) 最後\n"
    expected = " 1. 最初\n 2. 次\n 3. 最後\n"
    assert_equal expected, convert(rrd)
  end

  def test_text_number_to_bold
    rrd = "1. テキスト\n"
    expected = "**1.** テキスト\n"
    assert_equal expected, convert(rrd)
  end

  # C1: インデントコードブロック +3

  def test_indented_code_block
    rrd = "説明\n  code line 1\n  code line 2\n\n次の段落\n"
    expected = "説明\n`````\ncode line 1\ncode line 2\n`````\n\n次の段落\n"
    assert_equal expected, convert(rrd)
  end

  def test_indented_code_block_8spaces
    rrd = "説明\n        code\n\n"
    expected = "説明\n```````````\ncode\n```````````\n\n"
    assert_equal expected, convert(rrd)
  end

  # Step 12: 定義リスト

  def test_definition_list
    rrd = ": type\n  Content-Type header\n"
    expected = "- **`type`**:\n  Content-Type header\n"
    assert_equal expected, convert(rrd)
  end

  def test_definition_list_multiple
    rrd = ": type\n  Content-Type header\n: charset\n  Character set\n"
    expected = "- **`type`**:\n  Content-Type header\n- **`charset`**:\n  Character set\n"
    assert_equal expected, convert(rrd)
  end

  def test_definition_list_multiline
    rrd = ": [ ]\n  鈎括弧内のいずれかの文字と一致します。- でつな\n  がれた文字は範囲を表します。\n"
    expected = "- **`[ ]`**:\n  鈎括弧内のいずれかの文字と一致します。- でつな\n  がれた文字は範囲を表します。\n"
    assert_equal expected, convert(rrd)
  end

  # __WORD__ コードスパン変換

  def test_add_code_spans_basic
    assert_match(/`__END__`/, convert("__END__ を使う\n"))
  end

  # Step 13: 統合テスト — Comparable ラウンドトリップ

  def test_comparable_roundtrip
    rrd_path = File.expand_path('../../doctree/refm/api/src/_builtin/Comparable', __dir__)
    omit 'doctree not found' unless File.exist?(rrd_path)

    require 'bitclust/markdown_to_rrd'
    require 'bitclust/methoddatabase'
    require 'bitclust/rrdparser'

    params = {"version" => "3.4"}

    # Original → parse
    db1 = BitClust::MethodDatabase.dummy(params)
    lib1 = BitClust::RRDParser.new(db1).parse_file(rrd_path, "_builtin", params)

    # RRD → MD → RRD → parse
    rrd = File.read(rrd_path)
    md = BitClust::RRDToMarkdown.convert(rrd)
    rrd2 = BitClust::MarkdownToRRD.convert(md)

    require 'tempfile'
    Tempfile.create(['comparable', '.rrd']) do |f|
      f.write(rrd2)
      f.flush
      db2 = BitClust::MethodDatabase.dummy(params)
      lib2 = BitClust::RRDParser.new(db2).parse_file(f.path, "_builtin", params)

      # 同じクラス/メソッド構造であることを検証
      orig_methods = lib1.classes.first.entries.map(&:names)
      roundtrip_methods = lib2.classes.first.entries.map(&:names)
      assert_equal orig_methods, roundtrip_methods
    end
  end
end

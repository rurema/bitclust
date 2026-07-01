# frozen_string_literal: true

require 'test/unit'

require 'bitclust/markdown_to_rrd'

class TestMarkdownToRRD < Test::Unit::TestCase
  def convert(md)
    BitClust::MarkdownToRRD.convert(md)
  end

  # Step 1: H1 ヘッダ変換とパススルー

  def test_module_header
    assert_equal "= module Comparable\n",
      convert("# module Comparable\n")
  end

  def test_class_header_with_superclass
    assert_equal "= class Array < Object\n",
      convert("# class Array < Object\n")
  end

  def test_reopen_header
    assert_equal "= reopen Kernel\n",
      convert("# reopen Kernel\n")
  end

  def test_text_passthrough
    md = "# module Comparable\n\n説明文。\n"
    expected = "= module Comparable\n\n説明文。\n"
    assert_equal expected, convert(md)
  end

  def test_directive_passthrough
    md = "# module Comparable\n\n\#@since 2.4.0\ntext\n\#@end\n"
    expected = "= module Comparable\n\n\#@since 2.4.0\ntext\n\#@end\n"
    assert_equal expected, convert(md)
  end

  def test_comment_passthrough
    md = "\#@# これはコメント\n"
    expected = "\#@# これはコメント\n"
    assert_equal expected, convert(md)
  end

  def test_include_passthrough
    md = "\#@include(io/buffer.md)\n"
    expected = "\#@include(io/buffer.md)\n"
    assert_equal expected, convert(md)
  end

  # Step 2: H2 セクションヘッダ

  def test_h2_instance_methods
    assert_equal "== Instance Methods\n",
      convert("## Instance Methods\n")
  end

  def test_h2_class_methods
    assert_equal "== Class Methods\n",
      convert("## Class Methods\n")
  end

  def test_h2_constants
    assert_equal "== Constants\n",
      convert("## Constants\n")
  end

  def test_h2_module_functions
    assert_equal "== Module Functions\n",
      convert("## Module Functions\n")
  end

  # Step 3: メソッドシグネチャ + コードブロック

  def test_instance_method_signature
    assert_equal "--- ==(other) -> bool\n",
      convert("### def ==(other) -> bool\n")
  end

  def test_method_signature_with_block
    assert_equal "--- each {|item| ... } -> self\n",
      convert("### def each {|item| ... } -> self\n")
  end

  def test_multiple_signatures
    md = "### def [](nth) -> object | nil\n### def at(nth) -> object | nil\n"
    expected = "--- [](nth) -> object | nil\n--- at(nth) -> object | nil\n"
    assert_equal expected, convert(md)
  end

  def test_code_block_without_title
    md = "```ruby\n1 == 1   # => true\n```\n"
    expected = "\#@samplecode\n1 == 1   # => true\n\#@end\n"
    assert_equal expected, convert(md)
  end

  def test_code_block_with_title
    md = "```ruby title=\"例\"\n1 == 1\n```\n"
    expected = "\#@samplecode 例\n1 == 1\n\#@end\n"
    assert_equal expected, convert(md)
  end

  def test_code_block_without_language
    md = "```\nplain text\n```\n"
    expected = "//emlist{\nplain text\n//}\n"
    assert_equal expected, convert(md)
  end

  def test_code_block_title_with_backslash
    md = "```ruby title=\"C:\\\\path\"\ncode\n```\n"
    expected = "\#@samplecode C:\\path\ncode\n\#@end\n"
    assert_equal expected, convert(md)
  end

  def test_code_block_lang_without_title
    md = "```sh\necho hello\n```\n"
    expected = "//emlist[][sh]{\necho hello\n//}\n"
    assert_equal expected, convert(md)
  end

  def test_code_block_longer_fence
    md = "````ruby\ncode\n````\n"
    expected = "\#@samplecode\ncode\n\#@end\n"
    assert_equal expected, convert(md)
  end

  def test_code_block_longer_fence_not_closed_by_shorter
    md = "````ruby\ncode\n```\nmore\n````\n"
    expected = "\#@samplecode\ncode\n```\nmore\n\#@end\n"
    assert_equal expected, convert(md)
  end

  # Step 4: self. → ClassName. 変換

  def test_classname_method_preserved
    md = <<~MD
      # class Array < Object

      ## Class Methods

      ### def Array.try_convert(obj) -> Array | nil
    MD
    result = convert(md)
    assert_match(/\A--- Array\.try_convert/, result.lines[4])
  end

  def test_module_function_to_rrd
    md = <<~MD
      # module Benchmark

      ## Module Functions

      ### module_function def measure(label) -> Benchmark::Tms
    MD
    result = convert(md)
    assert_match(/--- measure\(label\)/, result)
  end

  # Step 5: 定数・グローバル変数

  def test_constant_signature
    assert_equal "--- CR -> String\n",
      convert("### const CR -> String\n")
  end

  def test_constant_without_arrow
    assert_equal "--- START\n",
      convert("### const START\n")
  end

  def test_global_variable_signature
    assert_equal "--- $DEBUG -> bool\n",
      convert("### gvar $DEBUG -> bool\n")
  end

  # module_function

  def test_module_function_signature
    assert_equal "--- measure(label) -> Benchmark::Tms\n",
      convert("### module_function def measure(label) -> Benchmark::Tms\n")
  end

  # ClassName.method はそのまま保持

  def test_class_method_keeps_classname
    assert_equal "--- Array.try_convert(obj) -> Array\n",
      convert("### def Array.try_convert(obj) -> Array\n")
  end

  # .? → .# 参照変換

  def test_module_function_ref_roundtrip
    assert_equal "[[m:Kernel.#open]]\n",
      convert("[m:Kernel?.open]\n")
  end

  # Step 6: param/return/raise メタデータ

  def test_param
    assert_equal "@param other 自身と比較したいオブジェクトを指定します。\n",
      convert("- **param** `other` -- 自身と比較したいオブジェクトを指定します。\n")
  end

  def test_raise
    assert_equal "@raise ArgumentError <=> が nil を返したときに発生します。\n",
      convert("- **raise** `ArgumentError` -- <=> が nil を返したときに発生します。\n")
  end

  def test_return_without_type
    assert_equal "@return 説明\n",
      convert("- **return** -- 説明\n")
  end

  def test_return_with_type
    assert_equal "@return 説明\n",
      convert("- **return** `String` -- 説明\n")
  end

  def test_metadata_continuation_line
    md = "- **raise** `ArgumentError` -- self <=> min か、self <=> max が nil を返\n                     したときに発生します。\n"
    expected = "@raise ArgumentError self <=> min か、self <=> max が nil を返\n                     したときに発生します。\n"
    assert_equal expected, convert(md)
  end

  # Step 7: SEE 参照

  def test_see_standalone
    assert_equal "@see [[m:String#-@]]\n",
      convert("**SEE** [m:String#-@]\n")
  end

  def test_see_multiple
    assert_equal "@see [[m:Array#-]], [[m:Array#union]]\n",
      convert("**SEE** [m:Array#-], [m:Array#union]\n")
  end

  def test_see_with_different_types
    assert_equal "@see [[d:spec/m17n]]\n",
      convert("**SEE** [d:spec/m17n]\n")
  end

  # Step 8: クロスリファレンス（インライン）

  def test_inline_class_ref
    assert_equal "[[c:String]] を参照。\n",
      convert("[c:String] を参照。\n")
  end

  def test_inline_method_ref
    assert_equal "[[m:Array#each]] と同じ。\n",
      convert("[m:Array#each] と同じ。\n")
  end

  def test_inline_ref_with_surrounding_text
    assert_equal "[[m:Array#dup]] 同様\n",
      convert("[m:Array#dup] 同様\n")
  end

  def test_inline_lib_ref
    assert_equal "[[lib:json]] を使う。\n",
      convert("[lib:json] を使う。\n")
  end

  def test_inline_ref_not_in_code_block
    md = "```ruby\n[c:String]\n```\n"
    expected = "\#@samplecode\n[c:String]\n\#@end\n"
    assert_equal expected, convert(md)
  end

  def test_inline_multiple_refs_in_line
    assert_equal "[[c:Array]] と [[c:Hash]] を使う。\n",
      convert("[c:Array] と [c:Hash] を使う。\n")
  end

  # Step 9: アンカー付き見出し・H4

  def test_h3_with_anchor
    assert_equal "===[a:mutable] 破壊的な変更\n",
      convert("### 破壊的な変更 {#mutable}\n")
  end

  def test_h4_heading
    assert_equal "==== 小見出し\n",
      convert("#### 小見出し\n")
  end

  def test_h4_with_anchor
    assert_equal "====[a:detail] 詳細\n",
      convert("#### 詳細 {#detail}\n")
  end

  # Step 10: YAML front matter

  def test_include_metadata_passthrough
    md = "# class Array < Object\ninclude Enumerable\n\n説明\n"
    expected = "= class Array < Object\ninclude Enumerable\n\n説明\n"
    assert_equal expected, convert(md)
  end

  def test_multiple_includes_passthrough
    md = "# class Array < Object\ninclude Enumerable\ninclude Comparable\n"
    expected = "= class Array < Object\ninclude Enumerable\ninclude Comparable\n"
    assert_equal expected, convert(md)
  end

  def test_extend_passthrough
    md = "# class Foo < Object\nextend Forwardable\n"
    expected = "= class Foo < Object\nextend Forwardable\n"
    assert_equal expected, convert(md)
  end

  def test_alias_passthrough
    md = "# class Integer < Numeric\nalias Fixnum\n"
    expected = "= class Integer < Numeric\nalias Fixnum\n"
    assert_equal expected, convert(md)
  end

  def test_front_matter_category
    md = "---\ncategory: Network\n---\nライブラリの説明\n"
    expected = "category Network\n\nライブラリの説明\n"
    assert_equal expected, convert(md)
  end

  def test_front_matter_require
    md = "---\nrequire:\n  - cgi/core\n  - cgi/cookie\n---\nライブラリの説明\n"
    expected = "require cgi/core\nrequire cgi/cookie\n\nライブラリの説明\n"
    assert_equal expected, convert(md)
  end

  def test_front_matter_sublibrary
    md = "---\nsublibrary:\n  - json/ext\n---\nライブラリの説明\n"
    expected = "sublibrary json/ext\n\nライブラリの説明\n"
    assert_equal expected, convert(md)
  end

  def test_front_matter_category_and_require
    md = "---\ncategory: Network\nrequire:\n  - socket\n---\nライブラリの説明\n"
    expected = "category Network\n\nrequire socket\n\nライブラリの説明\n"
    assert_equal expected, convert(md)
  end

  # Step 11: リスト変換

  def test_list_items
    md = "- self が other より大きいなら正の整数\n- self と other が等しいなら 0\n"
    expected = " * self が other より大きいなら正の整数\n * self と other が等しいなら 0\n"
    assert_equal expected, convert(md)
  end

  def test_list_items_with_indent_preserved
    # B4: 元のインデント幅を保持
    md = " - item1\n - item2\n"
    expected = " * item1\n * item2\n"
    assert_equal expected, convert(md)
  end

  def test_list_items_with_2space_indent
    md = "  - item1\n  - item2\n"
    expected = "  * item1\n  * item2\n"
    assert_equal expected, convert(md)
  end

  def test_list_not_confused_with_metadata
    md = "- **param** `x` -- 説明\n- 普通のリスト\n"
    expected = "@param x 説明\n * 普通のリスト\n"
    assert_equal expected, convert(md)
  end

  # Step 12: 定義リスト

  def test_definition_list_dash_format
    md = "- **type** -- Content-Type header\n"
    expected = ": type\n  Content-Type header\n"
    assert_equal expected, convert(md)
  end

  def test_definition_list_colon_format
    md = "- **type**: Content-Type header\n"
    expected = ": type\n  Content-Type header\n"
    assert_equal expected, convert(md)
  end

  def test_definition_list_colon_multiple
    md = "- **type**: Content-Type header\n- **charset**: Character set\n"
    expected = ": type\n  Content-Type header\n: charset\n  Character set\n"
    assert_equal expected, convert(md)
  end

  # Step 13: 統合テスト — Comparable

  def test_comparable_integration
    md_path = File.expand_path('../../samples/Comparable.v2.md', __dir__)
    omit 'samples/Comparable.v2.md not found' unless File.exist?(md_path)

    md = File.read(md_path)
    result = convert(md)

    # 構造的に正しい RRD が生成されていることを検証
    assert_match(/\A= module Comparable\n/, result)
    assert_match(/^== Instance Methods\n/, result)
    assert_match(/^--- ==\(other\) -> bool$/, result)
    assert_match(/^--- >\(other\) -> bool$/, result)
    assert_match(/^--- >=\(other\) -> bool$/, result)
    assert_match(/^--- <\(other\) -> bool$/, result)
    assert_match(/^--- <=\(other\) -> bool$/, result)
    assert_match(/^--- between\?\(min, max\) -> bool$/, result)
    assert_match(/^--- clamp\(min, max\) -> object$/, result)
    assert_match(/^@param other/, result)
    assert_match(/^@param min/, result)
    assert_match(/^@raise ArgumentError/, result)
    assert_match(/^\#@samplecode/, result)
    assert_match(/^\#@end/, result)
    assert_match(/^\#@since 2\.4\.0/, result)
    assert_match(/^\#@since 2\.7\.0/, result)
    assert_match(/^\#@since 3\.0/, result)
  end

  # Bug fixes: サンプルファイル検証で発見

  def test_see_as_list_item
    # - **see** は @see に変換すべき
    assert_equal "@see [[d:spec/m17n]]\n",
      convert("- **see** [d:spec/m17n]\n")
  end

  def test_see_as_list_item_with_multiple_refs
    md = "- **see** [m:CGI.accept_charset], [m:CGI.accept_charset=]\n"
    expected = "@see [[m:CGI.accept_charset]], [[m:CGI.accept_charset=]]\n"
    assert_equal expected, convert(md)
  end

  def test_front_matter_no_leading_blank_line
    # front matter 後に余分な空行が出力されない
    md = "---\ninclude:\n  - Comparable\n---\n\n# class String < Object\n"
    result = convert(md)
    assert_match(/\A= class String < Object\n/, result)
  end

  def test_dlist_item_inline_refs
    # 定義リスト内のインライン参照が変換される
    md = "- **expires** -- 有効期限を [c:Time] で指定します。\n"
    expected = ": expires\n  有効期限を [[c:Time]] で指定します。\n"
    assert_equal expected, convert(md)
  end

  def test_metadata_inline_refs
    # @param 内のインライン参照が変換される
    md = "- **param** `options` -- [c:Hash] か文字列で指定します。\n"
    expected = "@param options [[c:Hash]] か文字列で指定します。\n"
    assert_equal expected, convert(md)
  end

  def test_see_with_hyphenated_ref_type
    # ruby-list: のようなハイフン付き参照型
    assert_equal "@see [[ruby-list:35911]]\n",
      convert("- **see** [ruby-list:35911]\n")
  end

  def test_inline_hyphenated_ref_type
    assert_equal "[[ruby-dev:12345]] を参照。\n",
      convert("[ruby-dev:12345] を参照。\n")
  end

  # A2: ] エスケープのラウンドトリップ

  def test_bracket_method_ref_roundtrip
    # [m:Hash#\[\]] → [[m:Hash#[] ]]
    assert_equal "[[m:Hash#[] ]]\n",
      convert("[m:Hash#\\[\\]]\n")
  end

  def test_bracket_method_in_text_roundtrip
    assert_equal "@see [[m:Hash#[] ]]\n",
      convert("@see [m:Hash#\\[\\]]\n")
  end

  # B2/B5: メタデータスペース保持

  def test_return_alignment_spaces_roundtrip
    # - **return** --      説明 → @return      説明
    assert_equal "@return      説明\n",
      convert("- **return** --      説明\n")
  end

  def test_param_spaces_roundtrip
    assert_equal "@param obj   説明\n",
      convert("- **param** `obj` --   説明\n")
  end

  # B3: @see 区切り保持

  def test_see_comma_no_space_roundtrip
    assert_equal "@see [[m:A]],[[m:B]]\n",
      convert("@see [m:A],[m:B]\n")
  end

  def test_see_comma_with_space_roundtrip
    assert_equal "@see [[m:A]], [[m:B]]\n",
      convert("@see [m:A], [m:B]\n")
  end

  # C1: インデントコード -3

  def test_indented_code_fenced
    md = "説明\n`````\ncode line 1\ncode line 2\n`````\n\n"
    expected = "説明\n  code line 1\n  code line 2\n\n"
    assert_equal expected, convert(md)
  end

  def test_indented_code_fenced_8spaces
    md = "説明\n```````````\ncode\n```````````\n\n"
    expected = "説明\n        code\n\n"
    assert_equal expected, convert(md)
  end

  def test_indented_code_preserves_inner_indent
    md = "説明\n````````\nif true\n  puts 1\nend\n````````\n\n"
    expected = "説明\n     if true\n       puts 1\n     end\n\n"
    assert_equal expected, convert(md)
  end

  def test_empty_title_treated_as_no_title
    md = "```ruby title=\"\"\ncode\n```\n"
    expected = "\#@samplecode\ncode\n\#@end\n"
    assert_equal expected, convert(md)
  end

  # 番号付きリスト

  def test_ordered_list
    md = "1. 最初の項目\n2. 次の項目\n3. 最後の項目\n"
    expected = " (1) 最初の項目\n (2) 次の項目\n (3) 最後の項目\n"
    assert_equal expected, convert(md)
  end

  def test_bold_number_to_text
    md = "**1.** テキスト\n"
    expected = "1. テキスト\n"
    assert_equal expected, convert(md)
  end

  # リスト項目のスペース保持

  def test_list_item_preserves_multiple_spaces
    md = "-   item\n"
    expected = " *   item\n"
    assert_equal expected, convert(md)
  end

end

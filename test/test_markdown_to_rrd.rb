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

  def test_h3_with_hyphenated_anchor
    # doctree/manual の glossary.md 等、用語アンカーはハイフン区切り
    assert_equal "===[a:thread-safe] スレッドセーフ\n",
      convert("### スレッドセーフ {#thread-safe}\n")
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

  def test_front_matter_include_to_body
    md = "---\ninclude:\n  - Enumerable\n---\n# class Array < Object\n\n説明\n"
    expected = "= class Array < Object\ninclude Enumerable\n\n説明\n"
    assert_equal expected, convert(md)
  end

  def test_front_matter_multiple_includes_to_body
    md = "---\ninclude:\n  - Enumerable\n  - Comparable\n---\n# class Array < Object\n"
    expected = "= class Array < Object\ninclude Enumerable\ninclude Comparable\n"
    assert_equal expected, convert(md)
  end

  def test_front_matter_extend_to_body
    md = "---\nextend:\n  - Forwardable\n---\n# class Foo < Object\n"
    expected = "= class Foo < Object\nextend Forwardable\n"
    assert_equal expected, convert(md)
  end

  def test_front_matter_alias_to_body
    md = "---\nalias:\n  - Fixnum\n---\n# class Integer < Numeric\n"
    expected = "= class Integer < Numeric\nalias Fixnum\n"
    assert_equal expected, convert(md)
  end

  def test_front_matter_relations_grammar_order
    # RRD 文法順（alias → extend → include）で body に復元する
    md = "---\ninclude:\n  - I\nextend:\n  - E\nalias:\n  - A\n---\n# class Foo < Object\n"
    expected = "= class Foo < Object\nalias A\nextend E\ninclude I\n"
    assert_equal expected, convert(md)
  end

  def test_front_matter_versioned_alias_to_body
    # front matter 内の #@ を保持して body に復元する（YAML コメントで失わない）
    md = "---\nalias:\n\#@until 3.2\n  - Fixnum\n  - Bignum\n\#@end\n---\n# class Integer < Numeric\n\n説明\n"
    expected = "= class Integer < Numeric\n\#@until 3.2\nalias Fixnum\nalias Bignum\n\#@end\n\n説明\n"
    assert_equal expected, convert(md)
  end

  def test_front_matter_versioned_require_to_body
    md = "---\ncategory: Network\nrequire:\n\#@since 1.9.1\n  - cgi/core\n  - cgi/cookie\n\#@end\n---\n説明\n"
    expected = "category Network\n\n\#@since 1.9.1\nrequire cgi/core\nrequire cgi/cookie\n\#@end\n\n説明\n"
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

  def test_front_matter_name_is_dropped
    # name: は md 側のファイル名衝突回避（rdoc/rdoc.lib.md）でライブラリ名を
    # 保持するための md 専用キー。rd には現れない
    md = "---\ntype: library\nname: rdoc/rdoc\n---\nライブラリの説明\n"
    assert_equal "ライブラリの説明\n", convert(md)
  end

  def test_front_matter_category_and_require
    md = "---\ncategory: Network\nrequire:\n  - socket\n---\nライブラリの説明\n"
    expected = "category Network\n\nrequire socket\n\nライブラリの説明\n"
    assert_equal expected, convert(md)
  end

  def test_front_matter_gated_category_is_restored
    # cmath 型の据え置きゲート: ゲート付き category は #@ 行ごと復元する
    md = "---\n\#@since 1.9.1\ncategory: Math\n\#@end\n---\n" \
         "\#@since 1.9.1\n本文。\n\#@end\n"
    expected = "\#@since 1.9.1\ncategory Math\n\#@end\n\n" \
               "\#@since 1.9.1\n本文。\n\#@end\n"
    assert_equal expected, convert(md)
  end

  def test_front_matter_gated_metadata_blocks_are_restored
    # regate_metadata 形: require と sublibrary が別々のゲートブロック
    md = "---\n" \
         "require:\n\#@since 1.9.1\n  - a\n  - b\n\#@end\n" \
         "sublibrary:\n\#@since 1.9.1\n  - s\n\#@end\n" \
         "---\n" \
         "\#@since 1.9.1\n本文。\n\#@end\n"
    expected = "\#@since 1.9.1\nrequire a\nrequire b\n\#@end\n\n" \
               "\#@since 1.9.1\nsublibrary s\n\#@end\n\n" \
               "\#@since 1.9.1\n本文。\n\#@end\n"
    assert_equal expected, convert(md)
  end

  def test_front_matter_gated_library_list_is_dropped
    # 多重所属のゲート付き library リスト（注入キー）は md→rd で完全に捨てる。
    # ブロック内の #@ 行が leading コメント扱いで本文へ漏れないこと
    md = "---\n" \
         "library:\n" \
         "  - _builtin\n" \
         "\#@until 1.9.1\n" \
         "  - thread\n" \
         "\#@end\n" \
         "---\n" \
         "# class Mutex < Object\n\n説明\n"
    assert_equal "= class Mutex < Object\n\n説明\n", convert(md)
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

  # ---- doc ツリー対応: リテラルエスケープの復元 ----

  def test_escaped_bare_ref_is_unescaped_literally
    # rd→md が「参照に見えるリテラル」を \[ でエスケープしたものを復元する
    assert_equal "  [ruby-talk:198440] を参照。\n",
      convert("  \\[ruby-talk:198440] を参照。\n")
  end

  def test_unescaped_bare_ref_is_still_restored
    assert_equal "[[m:Array#each]] を参照。\n", convert("[m:Array#each] を参照。\n")
  end

  def test_escaped_leading_hash_is_unescaped
    assert_equal "# : 2002-08-01 IO#read\n#    本文。\n",
      convert("\\# : 2002-08-01 IO#read\n\\#    本文。\n")
  end

  def test_anchored_h1_restores
    assert_equal "=[a:ruby] Rubyの起動\n", convert("# Rubyの起動 {#ruby}\n")
  end

  def test_heading_trailing_space_restores
    assert_equal "=== 2004-12-06 \n", convert("### 2004-12-06 \n")
  end

  # ---- restore_description: entry description 用の rd 表示テキスト復元 ----

  def test_restore_description_list_markers
    # DublinCoreModel 型: description（先頭段落）がリストのとき、
    # md の行頭マーカーを rd 表示（* / (N)）へ戻す
    assert_equal "* [[url:http://example.org/]]",
      BitClust::MarkdownToRRD.restore_description("- [url:http://example.org/]")
    assert_equal "(1) 一つ目\n(2) 二つ目",
      BitClust::MarkdownToRRD.restore_description("1. 一つ目\n2. 二つ目")
    # **N.** の太字番号（rd では離散番号テキスト）は N. のまま戻し、
    # olist 復元で (N) 化しない
    assert_equal "1. 番号テキスト",
      BitClust::MarkdownToRRD.restore_description("**1.** 番号テキスト")
  end

  def test_restore_description_heading
    # doc/help 型: description（先頭段落）が見出しのとき md 記法を rd 表示へ
    assert_equal "=== 記号の説明",
      BitClust::MarkdownToRRD.restore_description("### 記号の説明")
    assert_equal "===[a:str] 特別な文字列に対するマッチ",
      BitClust::MarkdownToRRD.restore_description("### 特別な文字列に対するマッチ {#str}")
    # ハイフン入りアンカー（doctree/manual の glossary.md 用語アンカー等）も
    # プレースホルダ往復（\x00...\x00 → [a:...]）を経て正しく復元される
    assert_equal "===[a:thread-safe] スレッドセーフ",
      BitClust::MarkdownToRRD.restore_description("### スレッドセーフ {#thread-safe}")
  end

  def test_restore_description_metadata
    # CGI.escapeElement / ACL 型: @param・@see が先頭段落に来る
    assert_equal "@param string 文字列を指定します。",
      BitClust::MarkdownToRRD.restore_description("- **param** `string` -- 文字列を指定します。")
    assert_equal "@see [[m:ACL.new]]",
      BitClust::MarkdownToRRD.restore_description("- **SEE** [m:ACL.new]")
    assert_equal "@param bool 真偽値。\n@see [[m:BasicSocket#do_not_reverse_lookup]]",
      BitClust::MarkdownToRRD.restore_description(
        "- **param** `bool` -- 真偽値。\n- **SEE** [m:BasicSocket#do_not_reverse_lookup]")
    assert_equal "@raise TypeError 型が合わないとき。",
      BitClust::MarkdownToRRD.restore_description("- **raise** `TypeError` -- 型が合わないとき。")
    assert_equal "@return 結果。",
      BitClust::MarkdownToRRD.restore_description("- **return** -- 結果。")
  end

  def test_restore_description_fences
    # Addrinfo 型: 段落先頭がフェンス（閉じは次の段落へ切れている）
    assert_equal "  require 'socket'",
      BitClust::MarkdownToRRD.restore_description("`````\nrequire 'socket'")
    # LL2NUM 型: 説明行にフェンスブロックが直結（閉じフェンスあり）
    assert_equal "説明。\n   long long n = 42;\n   VALUE num = LL2NUM(n);",
      BitClust::MarkdownToRRD.restore_description("説明。\n``````\nlong long n = 42;\nVALUE num = LL2NUM(n);\n``````")
    # ENV.each 型: ```ruby は旧経路（前処理後）の //emlist 形へ。
    # フェンス内容行は復元を受けない（# => が見出し復元で壊れない）
    assert_equal "//emlist[][ruby]{\nENV['FOO'] = 'bar'\n# => ENV\n//}",
      BitClust::MarkdownToRRD.restore_description("```ruby\nENV['FOO'] = 'bar'\n# => ENV\n```")
    assert_equal "//emlist[例][ruby]{\np [c:String]\n//}",
      BitClust::MarkdownToRRD.restore_description("```ruby title=\"例\"\np [c:String]\n```")
    assert_equal "//emlist{\nplain - text\n//}",
      BitClust::MarkdownToRRD.restore_description("```\nplain - text\n```")
  end

  def test_restore_description_escapes
    # stat_col 型: 行頭 # のエスケープ、symref 型: \` のエスケープ
    assert_equal "#ifdef HASH_LOG のときだけ定義される、開発者用関数。",
      BitClust::MarkdownToRRD.restore_description("\\#ifdef HASH_LOG のときだけ定義される、開発者用関数。")
    assert_equal "付記B: `未定義` の振る舞いの例",
      BitClust::MarkdownToRRD.restore_description("付記B: \\`未定義\\` の振る舞いの例")
  end

  # ---- メタデータ領域の #@# コメントの復元（irb.rd 対応）----

  def test_leading_comment_restores_before_category
    md = "---\n\#@# Author: Keiju\ncategory: Development\n---\n本文。\n"
    assert_equal "\#@# Author: Keiju\n\ncategory Development\n\n本文。\n", convert(md)
  end

  def test_comment_inside_require_block_restores
    md = "---\ncategory: Development\nrequire:\n  - b\n\#@# note\n  - c\n---\n本文。\n"
    assert_equal "category Development\n\nrequire b\n\#@# note\nrequire c\n\n本文。\n", convert(md)
  end

end

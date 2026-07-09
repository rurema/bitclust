# frozen_string_literal: true

require 'test/unit'

require 'bitclust/entity_splitter'
require 'bitclust/include_graph'

# EntitySplitter: マルチエンティティ RRD をエンティティ単位に分割する（O3）。
# 2段階:
# 1. resolve_header_gates — スコープ定数（常に真/偽）の版ゲートのうち、最初の内容行が
#    エンティティ H1 のブロックを解決する（活きている枝を残しゲートを外す）。
#    版で改名されたエンティティ（thread/Mutex, Net::HTTPURITooLong 等）の H1 ペアが
#    スコープ内の単一 H1 に収束し、旧名は活き枝の alias 行として残る。
# 2. segments — 深さ0の H1（またはスコープ内ゲート付き H1 ブロック）を境界に分割。
#    セグメント間の内容は直前のエンティティに帰属。連結すると入力に一致する。
#
# テストリスト:
# [x] resolve: 常真 since + #@else 改名ペア → 活き枝のみ（thread/Mutex パターン）
# [x] resolve: 常偽 until + #@else → else 枝のみ
# [x] resolve: 常真ゲートがエンティティ全体を包む（else なし）→ unwrap（EarlyHints パターン）
# [x] resolve: 常偽ゲートがエンティティ全体を包む（else なし）→ ブロックごと除去
# [x] resolve: スコープ内ゲート（since 3.2 等）→ 据え置き
# [x] resolve: 散文を包むゲート（最初の内容行が H1 でない）→ 据え置き
# [x] resolve: ブロック内にネストした #@ があっても対応を取る
# [x] resolve: 活き枝に複数エンティティがあってもそのまま残す（base64 パターン）
# [x] segments: 裸 H1 で分割、内容は直前エンティティへ、連結=入力
# [x] segments: スコープ内ゲート付き H1 ブロックは丸ごと1セグメント
# [x] segments: #@samplecode 内の「= class」風の行は境界にしない
# [x] segments: 先頭に H1 以外の内容がある場合は nil
# [x] entity_filename: :: → __、. は保持
class TestEntitySplitter < Test::Unit::TestCase
  def scope
    BitClust::IncludeGraph::Scope.new("3.0", "4.2")
  end

  def resolve(src)
    BitClust::EntitySplitter.resolve_header_gates(src, scope)
  end

  def segments(src)
    BitClust::EntitySplitter.segments(src)
  end

  # ---- resolve_header_gates ----

  def test_resolve_renamed_entity_keeps_active_branch
    # thread/Mutex: #@since 2.3.0（常真）で改名された H1 ペア
    src = <<~RRD
      \#@since 2.3.0
      = class Thread::Mutex < Object
      alias Mutex
      \#@else
      = class Mutex < Object
      \#@end

      本文。
    RRD
    expected = <<~RRD
      = class Thread::Mutex < Object
      alias Mutex

      本文。
    RRD
    assert_equal expected, resolve(src)
  end

  def test_resolve_never_until_with_else_keeps_else_branch
    src = "\#@until 2.3.0\n= class Old < Object\n\#@else\n= class New < Object\n\#@end\n本文。\n"
    assert_equal "= class New < Object\n本文。\n", resolve(src)
  end

  def test_resolve_unwraps_wholly_gated_entity
    # Net::HTTPEarlyHints: #@since 2.6.0（常真）がエンティティ全体を包む
    src = "= class A < B\n\n\#@since 2.6.0\n= class C < D\n説明。\n\#@end\n\n= class E < F\n"
    assert_equal "= class A < B\n\n= class C < D\n説明。\n\n= class E < F\n", resolve(src)
  end

  def test_resolve_drops_never_gated_entity
    src = "= class A < B\n\n\#@until 2.4.0\n= class Dead < B\n説明。\n\#@end\n\n= class E < F\n"
    assert_equal "= class A < B\n\n= class E < F\n", resolve(src)
  end

  def test_resolve_keeps_in_scope_gate
    src = "\#@since 3.2\n= class New < Object\n説明。\n\#@end\n"
    assert_equal src, resolve(src)
  end

  def test_resolve_keeps_prose_gates
    src = "= class A < B\n\#@since 2.3.0\n新しい説明。\n\#@else\n古い説明。\n\#@end\n"
    assert_equal src, resolve(src)
  end

  def test_resolve_provably_true_if_gate_with_entities
    # digest.rd: #@if(version >= "1.8.6")（常真）がエンティティ構造ごと包む
    src = "\#@if(version >= \"1.8.6\")\n= class A < Object\n\n= class B < A\ninclude I\n\#@else\n= class B < Object\n\#@end\n共通。\n"
    assert_equal "= class A < Object\n\n= class B < A\ninclude I\n共通。\n", resolve(src)
  end

  def test_resolve_constant_gate_containing_h1_after_prose
    # syslog.rd: 常真ゲートが散文の後にエンティティ H1 を含む
    src = "= module C\n\n\#@since 2.0.0\n散文。\n= module D\nD。\n\#@end\n"
    assert_equal "= module C\n\n散文。\n= module D\nD。\n", resolve(src)
  end

  def test_resolve_keeps_relation_only_constant_gate
    # H1 を含まない定数ゲート（gated relations）は front matter の #@ 表現に任せる
    src = "= module C\n\#@since 2.0.0\ninclude X\n\#@end\n"
    assert_equal src, resolve(src)
  end

  def test_resolve_ignores_h1_like_lines_inside_samplecode
    src = "\#@since 2.0.0\n散文。\n\#@samplecode\n= class Fake < Object\n\#@end\n\#@end\n"
    assert_equal src, resolve(src)
  end

  def test_resolve_handles_quoted_version
    # Preprocessor は #@since "1.8.5" のクォート形式も受理する（_builtin/Process に実在）
    src = "\#@since \"1.8.5\"\n= class A < B\n本文。\n\#@end\n"
    assert_equal "= class A < B\n本文。\n", resolve(src)
  end

  def test_resolve_handles_nested_blocks
    src = <<~RRD
      \#@since 1.9.1
      = class A < B
      \#@since 2.0.0
      版分岐の説明。
      \#@end
      \#@end
    RRD
    expected = <<~RRD
      = class A < B
      \#@since 2.0.0
      版分岐の説明。
      \#@end
    RRD
    assert_equal expected, resolve(src)
  end

  def test_resolve_keeps_multi_entity_active_branch
    # base64/Base64: 常真ゲートの枝に複数エンティティ
    src = "\#@since 1.9.1\n= module Base64\n\n= reopen Kernel\n\#@else\n= module Base64\n\#@end\n"
    assert_equal "= module Base64\n\n= reopen Kernel\n", resolve(src)
  end

  # ---- segments ----

  def test_segments_split_at_bare_h1
    src = "= class A < Object\ninclude Foo\n\nA の説明。\n\n= class B < Object\nB の説明。\n"
    segs = segments(src)
    assert_equal ["A", "B"], segs.map(&:first)
    assert_equal "= class A < Object\ninclude Foo\n\nA の説明。\n\n", segs[0][1]
    assert_equal "= class B < Object\nB の説明。\n", segs[1][1]
    assert_equal src, segs.map(&:last).join
  end

  def test_segments_in_scope_gated_block_is_one_segment
    src = "= class A < Object\n\n\#@since 3.2\n= class New < Object\n説明。\n\#@end\n"
    segs = segments(src)
    assert_equal ["A", "New"], segs.map(&:first)
    assert_equal "\#@since 3.2\n= class New < Object\n説明。\n\#@end\n", segs[1][1]
  end

  def test_segments_partial_gate_around_h1_is_not_a_boundary
    # syslog の旧構造: H1 と見出しだけがゲートされ、定数群はゲートの外にある。
    # 単独ファイル化するとゲートが偽の版で自立パースできない
    # （旧世界では直前エンティティに付く）ので分割境界にしない
    src = "= class A < Object\n\n" \
          "\#@since 2.0.0\n= module B\n説明。\n== Constants\n\#@end\n" \
          "--- CONST -> Integer\n"
    segs = segments(src)
    assert_equal ["A"], segs.map(&:first)
    assert_equal src, segs[0][1]
  end

  def test_segments_gated_boundary_allows_trailing_blanks
    src = "= class A < Object\n\n" \
          "\#@since 3.2\n= class New < Object\n説明。\n\#@end\n\n"
    segs = segments(src)
    assert_equal ["A", "New"], segs.map(&:first)
  end

  def test_segments_ignores_h1_like_lines_in_samplecode
    src = "= class A < Object\n\#@samplecode\n= class B < Object\n\#@end\n"
    segs = segments(src)
    assert_equal ["A"], segs.map(&:first)
  end

  def test_segments_leading_content_becomes_base_segment
    # ライブラリファイルのインライン・エンティティ: 先頭のライブラリ概要部は
    # name=nil のベースセグメントになる
    src = "category Cat\n\n概要。\n\n= class A < Object\nA の説明。\n"
    segs = segments(src)
    assert_equal [nil, "A"], segs.map(&:first)
    assert_equal "category Cat\n\n概要。\n\n", segs[0][1]
    assert_equal src, segs.map(&:last).join
  end

  def test_segments_single_entity
    src = "= class A < Object\n説明。\n"
    assert_equal [["A", src]], segments(src)
  end

  # ---- header_relations? ----

  def test_header_relations_detects_relation_after_h1
    assert_true BitClust::EntitySplitter.header_relations?(
      "= class A < Object\ninclude Foo\n\n説明。\n")
    assert_true BitClust::EntitySplitter.header_relations?(
      "= class A < Object\n\n説明。\n\n= class B < Object\nalias C\n")
  end

  def test_header_relations_ignores_body_and_samplecode
    # 本文到達後の include 風の行（コード例等）は数えない
    assert_false BitClust::EntitySplitter.header_relations?(
      "= module Math\n\n説明。\n\n\#@samplecode\ninclude Math\n\#@end\n")
  end

  def test_header_relations_counts_gated_relations
    assert_true BitClust::EntitySplitter.header_relations?(
      "= class A < Object\n\#@since 2.6.0\nalias B\n\#@end\n\n説明。\n")
  end

  # ---- entity_filename ----

  def test_entity_filename
    assert_equal "Net__HTTPOK", BitClust::EntitySplitter.entity_filename("Net::HTTPOK")
    assert_equal "ARGF.class", BitClust::EntitySplitter.entity_filename("ARGF.class")
    assert_equal "Time", BitClust::EntitySplitter.entity_filename("Time")
  end
end

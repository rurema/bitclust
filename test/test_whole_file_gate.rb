# frozen_string_literal: true

require 'test/unit'

require 'bitclust/whole_file_gate'
require 'bitclust/include_graph'

# WholeFileGate: ファイル全体を包む単一の版ゲート（#@else 無し）を検出し、
# スコープの下で不要（常に真）または front matter の since/until で表現できる場合に
# ゲート行を外す（O4）。表現できないもの（#@else 付き、スコープ外）は据え置き。
#
# テストリスト:
# [x] ゲートで始まらないファイル → detect nil
# [x] #@end の後に内容が続く（部分ゲート）→ nil
# [x] ファイル全体を包む #@since/#@until/#@if → Condition
# [x] トップレベルに #@else がある（fiddle.rd）→ nil
# [x] 内部にネストしたゲート・#@samplecode があっても正しく対応を取る（rss.rd）
# [x] 先頭の空行はスキップして判定、#@end の後の空行は許容
# [x] unwrap: 開き/閉じ行を除去し、先頭に残る空行は削る（doctree 正規化と整合）
# [x] unwrap_for_scope: スコープ内で常に真の since → [unwrapped, {}]
# [x] unwrap_for_scope: in-scope の until（fiber/set）→ [unwrapped, {until: v}]
# [x] unwrap_for_scope: in-scope の since → [unwrapped, {since: v}]
# [x] unwrap_for_scope: スコープ外（until 2.7.0 等）→ nil（据え置き）
# [x] unwrap_for_scope: 常に真と証明できる #@if（version >= "X", X <= 下限）→ [unwrapped, {}]
# [x] unwrap_for_scope: その他の #@if 条件 → nil（据え置き）
class TestWholeFileGate < Test::Unit::TestCase
  def scope
    BitClust::IncludeGraph::Scope.new("3.0", "4.2")
  end

  def detect(src)
    BitClust::WholeFileGate.detect(src)
  end

  def unwrap_for_scope(src)
    BitClust::WholeFileGate.unwrap_for_scope(src, scope)
  end

  def test_detect_returns_nil_without_gate
    assert_nil detect("category Math\n\n本文。\n")
  end

  def test_detect_returns_nil_for_partial_gate
    # cgi/util.rd: 先頭ゲートがファイル途中で閉じる
    assert_nil detect("\#@since 1.9.1\n本文。\n\#@end\n続き。\n")
  end

  def test_detect_whole_file_since
    cond = detect("\#@since 1.9.1\n本文。\n\#@end\n")
    assert_equal :since, cond.kind
    assert_equal "1.9.1", cond.version
  end

  def test_detect_whole_file_if
    cond = detect("\#@if (version >= \"1.8.2\")\n本文。\n\#@end\n")
    assert_equal :if, cond.kind
    assert_equal '(version >= "1.8.2")', cond.version
  end

  def test_detect_returns_nil_with_top_level_else
    # fiddle.rd: #@until 2.0.0 ... #@else ... #@end
    assert_nil detect("\#@until 2.0.0\n古い。\n\#@else\n新しい。\n\#@end\n")
  end

  def test_detect_handles_nested_gates_and_samplecode
    src = "\#@since 1.9.1\n\#@until 3.0\n本文。\n\#@end\n\#@samplecode\ncode\n\#@end\n\#@end\n"
    cond = detect(src)
    assert_equal :since, cond.kind
  end

  def test_detect_skips_leading_and_trailing_blanks
    cond = detect("\n\#@since 1.9.1\n本文。\n\#@end\n\n")
    assert_equal :since, cond.kind
  end

  def test_unwrap_for_scope_vacuous_since
    # cmath.rd / _builtin/Encoding: #@since 1.9.1（+直後の空行）で全体が包まれる
    src = "\#@since 1.9.1\n\ncategory Math\n\n本文。\n\#@end\n"
    unwrapped, gate = unwrap_for_scope(src)
    assert_equal "category Math\n\n本文。\n", unwrapped
    assert_equal({}, gate)
  end

  def test_unwrap_for_scope_in_scope_until
    # fiber.rd: #@until 3.1
    src = "\#@until 3.1\n本文。\n\n\#@end\n"
    unwrapped, gate = unwrap_for_scope(src)
    assert_equal "本文。\n\n", unwrapped
    assert_equal({ until: "3.1" }, gate)
  end

  def test_unwrap_for_scope_in_scope_since
    src = "\#@since 3.2\n本文。\n\#@end\n"
    unwrapped, gate = unwrap_for_scope(src)
    assert_equal "本文。\n", unwrapped
    assert_equal({ since: "3.2" }, gate)
  end

  def test_unwrap_for_scope_leaves_out_of_scope_file
    # profile.rd / irb/slex.rd: until 2.7.0 は [3.0,4.2) の対象外
    assert_nil unwrap_for_scope("\#@until 2.7.0\n本文。\n\#@end\n")
  end

  def test_unwrap_for_scope_provably_true_if
    # rss.rd: (version >= "1.8.2") はスコープ下限 3.0 以下なので常に真
    src = "\#@if (version >= \"1.8.2\")\n本文。\n\#@end\n"
    unwrapped, gate = unwrap_for_scope(src)
    assert_equal "本文。\n", unwrapped
    assert_equal({}, gate)
  end

  def test_unwrap_for_scope_leaves_unprovable_if
    assert_nil unwrap_for_scope("\#@if (version == \"3.1\")\n本文。\n\#@end\n")
    assert_nil unwrap_for_scope("\#@if (version >= \"3.1\")\n本文。\n\#@end\n")
  end

  def test_unwrap_for_scope_returns_nil_without_whole_file_gate
    assert_nil unwrap_for_scope("category Math\n\n本文。\n")
  end
end

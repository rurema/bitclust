# frozen_string_literal: true

require 'test/unit'

require 'bitclust/include_pruner'

# IncludePruner: RRD テキストから指定 target の #@include 行を除去する純変換（rd→rd）。
# 新パイプラインでは grouping include（エンティティの取り込み）は glob + front matter の
# 発見に置き換わるため、ライブラリ概要ファイルから除去する。fragment include は温存。
#
# テストリスト:
# [x] target が無ければ入力を変更しない（バイト一致）
# [x] 指定 target の #@include 行を除去する
# [x] 指定外の target（fragment include）は残す
# [x] 連続する include 行の除去
# [x] 空行で区切られた include 群 → 空行が1つに畳まれる（net/http.rd パターン）
# [x] 除去で空になった版ゲートブロックはブロックごと除去（_builtin.rd の Bignum パターン）
# [x] ネストしたブロックが連鎖的に空になる場合も除去
# [x] #@else 枝の中の include 除去、枝に他の内容があればブロックは残る（thread.rd パターン）
# [x] 片枝だけ空になった #@else ブロックは構造を保持
# [x] 両枝とも空になったブロックは全体を除去
# [x] もともと空のブロックは（除去が起きなければ）そのまま
# [x] 末尾 include 除去後、直前の空行は保持する（continuation.rd/webrick/server.rd パターン。
#     メタデータ領域再生成の空行仕様と整合し md→rd がバイト一致する。空行終端は既存149ファイルと同スタイル）
# [x] ファイル先頭の include 除去で残る先頭空行は削る（doctree 正規化と整合）
# [x] #@samplecode ブロックは版ゲートとして扱わない（空でも除去しない）
class TestIncludePruner < Test::Unit::TestCase
  def prune(src, targets)
    BitClust::IncludePruner.prune(src, targets)
  end

  def test_no_targets_returns_input_unchanged
    src = "text\n\n\#@include(foo/Bar)\n"
    assert_equal src, prune(src, [])
    assert_equal src, prune(src, ["other/Target"])
  end

  def test_removes_matching_include_line
    src = "text\n\#@include(foo/Bar)\ntext2\n"
    assert_equal "text\ntext2\n", prune(src, ["foo/Bar"])
  end

  def test_keeps_non_matching_includes
    src = "\#@include(frag)\n\#@include(foo/Bar)\n"
    assert_equal "\#@include(frag)\n", prune(src, ["foo/Bar"])
  end

  def test_unbalanced_gates_leave_input_unchanged
    # 対応の取れない #@end を含むファイルは構造が判定できないので手を付けない
    src = "\#@end\n\#@include(a/A)\n"
    assert_equal src, prune(src, ["a/A"])
  end

  def test_removes_consecutive_includes
    src = "text\n\n\#@include(a/A)\n\#@include(a/B)\n\#@include(a/C)\n"
    assert_equal "text\n\n", prune(src, ["a/A", "a/B", "a/C"])
  end

  def test_collapses_blank_lines_between_removed_includes
    # net/http.rd: include が空行区切りで並ぶ
    src = "text\n\n\#@include(a/A)\n\n\#@include(a/B)\n\n\#@include(a/C)\n\ntext2\n"
    assert_equal "text\n\ntext2\n", prune(src, ["a/A", "a/B", "a/C"])
  end

  def test_removes_emptied_gate_block
    # _builtin.rd: #@until 2.4.0 / #@include(_builtin/Bignum) / #@end
    src = "\#@include(a/A)\n\#@until 2.4.0\n\#@include(a/B)\n\#@end\n\#@include(a/C)\n"
    assert_equal "", prune(src, ["a/A", "a/B", "a/C"])
  end

  def test_removes_nested_emptied_blocks
    src = "text\n\#@since 2.0.0\n\#@until 3.0\n\#@include(a/A)\n\#@end\n\#@end\n"
    assert_equal "text\n", prune(src, ["a/A"])
  end

  def test_keeps_block_when_branch_retains_content
    # thread.rd: #@else 枝に散文とエンティティ定義が残る
    src = <<~RRD
      \#@since 2.3.0
      新しい説明。
      \#@else
      古い説明。
      \#@until 1.9.1
      \#@include(thread/Mutex)
      \#@end
      \#@include(thread/Queue)
      \#@end
    RRD
    expected = <<~RRD
      \#@since 2.3.0
      新しい説明。
      \#@else
      古い説明。
      \#@end
    RRD
    assert_equal expected, prune(src, ["thread/Mutex", "thread/Queue"])
  end

  def test_keeps_block_structure_when_only_one_branch_empties
    src = "\#@until 2.0.0\n\#@include(a/Old)\n\#@else\n説明。\n\#@end\n"
    expected = "\#@until 2.0.0\n\#@else\n説明。\n\#@end\n"
    assert_equal expected, prune(src, ["a/Old"])
  end

  def test_removes_block_when_both_branches_empty
    src = "text\n\#@until 2.0.0\n\#@include(a/Old)\n\#@else\n\#@include(a/New)\n\#@end\n"
    assert_equal "text\n", prune(src, ["a/Old", "a/New"])
  end

  def test_keeps_preexisting_empty_block_without_removal
    src = "\#@since 2.0.0\n\#@end\ntext\n\#@include(a/A)\n"
    assert_equal "\#@since 2.0.0\n\#@end\ntext\n", prune(src, ["a/A"])
  end

  def test_keeps_preceding_blank_when_trailing_include_removed
    # continuation.rd: 本文 + 空行 + include で終わる。空行は保持する
    # （webrick/server.rd の require 群 + 空行 + include 群でも、md→rd の
    # メタデータ再生成が「require 群 + 空行」を出すため、保持しないと一致しない）
    src = "本文。\n\n\#@include(_builtin/Continuation)\n"
    assert_equal "本文。\n\n", prune(src, ["_builtin/Continuation"])
  end

  def test_strips_leading_blank_after_removal_at_bof
    src = "\#@include(a/A)\n\ntext\n"
    assert_equal "text\n", prune(src, ["a/A"])
  end

  def test_samplecode_block_is_not_a_gate_block
    # samplecode の #@end を版ゲートと混同すると対応が壊れる
    src = "\#@samplecode 例\ncode\n\#@end\n\#@since 3.0\n\#@include(a/A)\n\#@end\n"
    assert_equal "\#@samplecode 例\ncode\n\#@end\n", prune(src, ["a/A"])
  end
end

# frozen_string_literal: true

require 'test/unit'

require 'bitclust/doc_converter'
require 'bitclust/markdown_to_rrd'

# DocConverter: refm/doc（散文ページ）の md 変換。
# クロスファイル情報が無いので reduce（正規化）+ 単一ファイル変換のみ。
#
# reduce の正規化（意味を変えない表記ゆれを md→rd 再生成形に合わせる）:
# [x] ラベル無し #@samplecode の末尾スペース除去（spec/variables.rd）
# [x] //} の末尾スペース除去（spec/pattern_matching.rd）
# [x] 定義リスト term の「:  」二重スペース → 「: 」（spec/safelevel.rd, symref.rd）
# [x] 行頭タブ → スペース（news/2_7_0.rd の散文1行のみ。コード例にタブは無い）
# [x] クロスツリー include を manual レイアウトへ（../api/src/X → ../api/X）
# [x] convert(rrd) は reduce 後の変換で、md→rd が reduce 結果を復元する
class TestDocConverter < Test::Unit::TestCase
  def reduce(rrd)
    BitClust::DocConverter.reduce(rrd)
  end

  def test_samplecode_trailing_space
    assert_equal "\#@samplecode\ncode\n\#@end\n", reduce("\#@samplecode \ncode\n\#@end\n")
    # ラベル付きは触らない
    assert_equal "\#@samplecode 例\n", reduce("\#@samplecode 例\n")
  end

  def test_emlist_close_trailing_space
    assert_equal "//emlist{\ncode\n//}\n", reduce("//emlist{\ncode\n//} \n")
  end

  def test_dlist_term_double_space
    assert_equal ": Object#taint\n", reduce(":  Object#taint\n")
    assert_equal ": !true\n", reduce(":   !true\n")
  end

  def test_anchored_heading_double_space
    # spec/regexp.rd: ===[a:str]  特別な... （アンカー後の二重スペース）
    assert_equal "===[a:str] 特別な文字列に対するマッチ\n",
      reduce("===[a:str]  特別な文字列に対するマッチ\n")
  end

  def test_leading_tab_to_space
    assert_equal "  x\n lazy になりました。\n", reduce("  x\n\tlazy になりました。\n")
  end

  def test_cross_tree_include_rewritten_to_manual_layout
    assert_equal "\#@include(../api/_builtin/pack-template)\n",
      reduce("\#@include(../api/src/_builtin/pack-template)\n")
    assert_equal "\#@include(../../api/_builtin/thread.inc)\n",
      reduce("\#@include(../../api/src/_builtin/thread.inc)\n")
  end

  def test_convert_roundtrips_to_reduced
    rrd = "= タイトル\n\n本文。\n\n:  term\n  説明。\n"
    md = BitClust::DocConverter.convert(rrd)
    assert_equal reduce(rrd), BitClust::MarkdownToRRD.convert(md)
  end

  def test_files_selects_pages_and_referenced_fragments
    # 旧パイプライン（copy_doc）は **/*.rd だけをページとして読む。
    # .rd 以外は include 参照される断片（spec/regexp19）のみ変換し、
    # 参照されない死にファイル（news/1.8.0.rd-2）は凍結側に残す
    require 'tmpdir'
    require 'fileutils'
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "spec"))
      FileUtils.mkdir_p(File.join(dir, "news"))
      File.write(File.join(dir, "spec/regexp.rd"), "= 正規表現\n\#@include(regexp19)\n")
      File.write(File.join(dir, "spec/regexp19"), "断片。\n")
      File.write(File.join(dir, "news/1.8.0.rd"), "= news\n")
      File.write(File.join(dir, "news/1.8.0.rd-2"), "= 続き（孤児）\n")
      assert_equal ["news/1.8.0.rd", "spec/regexp.rd", "spec/regexp19"],
        BitClust::DocConverter.files(dir)
    end
  end
end

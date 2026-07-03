# frozen_string_literal: true

require 'test/unit'
require 'tmpdir'
require 'fileutils'

require 'bitclust/markdown_orchestrator'
require 'bitclust/markdown_to_rrd'

# MarkdownOrchestrator: RRD ツリー → Markdown ツリー変換のクロスファイル方針を
# 1か所に束ねる（グラフ解析 → prune → 全体ゲート解除 → front matter 注入）。
# bin/rrd2md --graph と tools/md-roundtrip-check.rb --inject の共通実装。
#
# テストリスト:
# [x] member には library を注入し、root からは grouping include を prune、
#     root には type: library を付ける
# [x] fragment include は温存される
# [x] 全体ゲート（常に真）は解除されて md にラッパーが残らない
# [x] LIBRARIES 由来のゲートとファイル全体ゲートは交差でマージされ二重にならない
# [x] reduce の rd と convert の md が MarkdownToRRD で一致（ラウンドトリップ期待値）
# [x] LIBRARIES 自体は変換対象外
class TestMarkdownOrchestrator < Test::Unit::TestCase
  FILES = {
    "LIBRARIES"  => "foo\n\#@until 3.1\ngated\n\#@end\n",
    "foo.rd"     => "category Cat\n\n説明。\n\n\#@include(foo/Bar)\n\n\#@include(foo/frag)\n",
    "foo/Bar"    => "\#@since 1.9.1\n= class Bar < Object\n\nBar の説明。\n\#@end\n",
    "foo/frag"   => "断片。\n",
    "gated.rd"   => "\#@until 3.1\ngated ライブラリの説明。\n\#@end\n",
  }.freeze

  def with_orchestrator
    Dir.mktmpdir do |dir|
      FILES.each do |path, content|
        full = File.join(dir, path)
        FileUtils.mkdir_p(File.dirname(full))
        File.write(full, content)
      end
      yield BitClust::MarkdownOrchestrator.new(dir)
    end
  end

  def test_root_conversion_prunes_groupings_and_marks_library
    with_orchestrator do |orch|
      md = orch.convert("foo.rd", FILES["foo.rd"])
      expected = <<~MD
        ---
        type: library
        category: Cat
        ---
        説明。

        \#@include(foo/frag)
      MD
      assert_equal expected, md
    end
  end

  def test_member_conversion_injects_library_and_unwraps_vacuous_gate
    with_orchestrator do |orch|
      md = orch.convert("foo/Bar", FILES["foo/Bar"])
      expected = <<~MD
        ---
        library: foo
        ---
        # class Bar < Object

        Bar の説明。
      MD
      assert_equal expected, md
    end
  end

  def test_library_gate_from_libraries_and_file_wrap_merge_once
    with_orchestrator do |orch|
      md = orch.convert("gated.rd", FILES["gated.rd"])
      expected = <<~MD
        ---
        type: library
        until: "3.1"
        ---
        gated ライブラリの説明。
      MD
      assert_equal expected, md
    end
  end

  def test_reduce_matches_markdown_to_rrd_of_convert
    with_orchestrator do |orch|
      FILES.each_key do |path|
        next unless orch.convert?(path)
        rrd = FILES[path]
        reduced, = orch.reduce(path, rrd)
        assert_equal reduced, BitClust::MarkdownToRRD.convert(orch.convert(path, rrd)),
          "roundtrip mismatch for #{path}"
      end
    end
  end

  def test_libraries_file_is_not_converted
    with_orchestrator do |orch|
      assert_false orch.convert?("LIBRARIES")
      assert_true orch.convert?("foo.rd")
    end
  end

  def test_entity_h1_without_space_is_normalized
    # _builtin/Encoding の「=class Encoding」。RRDParser は受理するが
    # 単一ファイル変換器は正規形「= class」のみ扱うため、reduce 段で正規化する
    with_orchestrator do |orch|
      rrd = "=class Enc\n\n説明。\n"
      reduced, = orch.reduce("foo/Enc", rrd)
      assert_equal "= class Enc\n\n説明。\n", reduced
      assert_equal "# class Enc\n\n説明。\n", orch.convert("foo/Enc", rrd)
    end
  end
end

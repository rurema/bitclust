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

  # ---- reduce のヘッダ正規化 ----
  # md→rd の再生成形（H1 直後に関係、末尾空白なし）に reduce 側を揃え、
  # byte-exact ラウンドトリップを成立させる

  def test_reduce_strips_leading_blank_after_resolution
    # base64/Base64: 解決で先頭に空行が残るケース
    with_orchestrator do |orch|
      rrd = "\#@since 1.9.1\n\n= module B\n\#@else\n= module Old\n\#@end\n"
      reduced, = orch.reduce("foo/Bar", rrd)
      assert_equal "= module B\n", reduced
    end
  end

  def test_reduce_strips_trailing_space_on_relation_lines
    # openssl/SSL__SSLSocket: 「include X 」の末尾スペース
    with_orchestrator do |orch|
      rrd = "= class A < Object\ninclude Foo \n\n説明。\n"
      reduced, = orch.reduce("foo/Bar", rrd)
      assert_equal "= class A < Object\ninclude Foo\n\n説明。\n", reduced
    end
  end

  def test_reduce_removes_blank_between_h1_and_relations
    # _builtin/Integer 等: H1 と（gated）関係の間の空行
    with_orchestrator do |orch|
      rrd = "= class A < Object\n\ninclude Foo\n\n説明。\n"
      reduced, = orch.reduce("foo/Bar", rrd)
      assert_equal "= class A < Object\ninclude Foo\n\n説明。\n", reduced

      rrd2 = "= class A < B\n\n\#@until 3.2\nalias F\n\#@end\n\n説明。\n"
      reduced2, = orch.reduce("foo/Bar", rrd2)
      assert_equal "= class A < B\n\#@until 3.2\nalias F\n\#@end\n\n説明。\n", reduced2
    end
  end

  def test_reduce_keeps_blank_after_h1_without_relations
    with_orchestrator do |orch|
      rrd = "= class A < Object\n\n説明。\n\#@since 3.0\n新しい。\n\#@end\n"
      reduced, = orch.reduce("foo/Bar", rrd)
      assert_equal rrd, reduced
    end
  end

  # ---- units: エンティティ分割（O3）----
  # ヘッダ関係を持つマルチエンティティファイルはエンティティ単位に分割し、
  # 関係を front matter に一元化する。関係なしの束ね（Errno 族等）は分割しない。

  def test_units_split_relation_bearing_multi_entity_file
    with_orchestrator do |orch|
      rrd = "= class Conf < Object\ninclude Enumerable\n\n説明。\n\n" \
            "= class Conf::Error < StandardError\nエラー。\n"
      units = orch.units("foo/Bar", rrd)
      assert_equal ["foo/Conf.md", "foo/Conf__Error.md"], units.map(&:path)
      assert_equal <<~MD, orch.convert_unit(units[0])
        ---
        library: foo
        include:
          - Enumerable
        ---
        # class Conf < Object

        説明。

      MD
      assert_equal <<~MD, orch.convert_unit(units[1])
        ---
        library: foo
        ---
        # class Conf::Error < StandardError
        エラー。
      MD
    end
  end

  def test_units_keep_relation_free_bundle_unsplit
    with_orchestrator do |orch|
      rrd = "= class E1 < StandardError\n説明1。\n\n= class E2 < StandardError\n説明2。\n"
      units = orch.units("foo/Bar", rrd)
      assert_equal ["foo/Bar.md"], units.map(&:path)
    end
  end

  def test_units_resolve_renamed_h1_into_single_entity
    # thread/Mutex パターン: 常真ゲートの改名 H1 ペア → 分割ではなく単一エンティティ化。
    # alias が front matter に上がる
    with_orchestrator do |orch|
      rrd = "\#@since 2.3.0\n= class T::Mutex < Object\nalias Mutex\n\#@else\n" \
            "= class Mutex < Object\n\#@end\n\n本文。\n"
      units = orch.units("foo/Bar", rrd)
      assert_equal ["foo/Bar.md"], units.map(&:path)
      assert_equal <<~MD, orch.convert_unit(units[0])
        ---
        library: foo
        alias:
          - Mutex
        ---
        # class T::Mutex < Object

        本文。
      MD
    end
  end

  def test_units_move_segment_gate_to_front_matter
    # スコープ内ゲート付きエンティティを含む分割: セグメントの全体ゲートが since に
    with_orchestrator do |orch|
      rrd = "= class Conf < Object\ninclude Enumerable\n\n説明。\n\n" \
            "\#@since 3.2\n= class Conf::New < Object\n新しい。\n\#@end\n"
      units = orch.units("foo/Bar", rrd)
      assert_equal ["foo/Conf.md", "foo/Conf__New.md"], units.map(&:path)
      assert_equal <<~MD, orch.convert_unit(units[1])
        ---
        library: foo
        since: "3.2"
        ---
        # class Conf::New < Object
        新しい。
      MD
    end
  end

  def test_units_single_entity_file_passes_through
    with_orchestrator do |orch|
      units = orch.units("foo/Bar", FILES["foo/Bar"])
      assert_equal ["foo/Bar.md"], units.map(&:path)
      assert_equal orch.convert("foo/Bar", FILES["foo/Bar"]), orch.convert_unit(units[0])
    end
  end

  def test_units_library_file_keeps_own_path
    with_orchestrator do |orch|
      units = orch.units("foo.rd", FILES["foo.rd"])
      assert_equal ["foo.md"], units.map(&:path)
    end
  end

  # ---- ライブラリファイルのインライン・エンティティ分割 ----

  def test_units_split_inline_entities_out_of_library_file
    # sdbm.rd 型: ライブラリ概要 + インライン・エンティティ複数（関係あり）。
    # エンティティは <libname>/ 配下へ、library を注入。概要部は元パスに残る
    with_orchestrator do |orch|
      rrd = "category Cat\n\n概要。\n\n= class A < Object\ninclude Enumerable\n\nA。\n\n= class A::E < StandardError\nE。\n"
      units = orch.units("foo.rd", rrd)
      assert_equal ["foo.md", "foo/A.md", "foo/A__E.md"], units.map(&:path)
      assert_equal <<~MD, orch.convert_unit(units[0])
        ---
        type: library
        category: Cat
        ---
        概要。

      MD
      assert_equal <<~MD, orch.convert_unit(units[1])
        ---
        library: foo
        include:
          - Enumerable
        ---
        # class A < Object

        A。

      MD
    end
  end

  def test_units_keep_dual_library_entity_file_unsplit
    # pathname 型（lib + 単一エンティティ兼用）は仕様が認める形なので分割しない
    with_orchestrator do |orch|
      rrd = "category Cat\n\n概要。\n\n= class A < Object\ninclude Enumerable\n\nA。\n"
      units = orch.units("foo.rd", rrd)
      assert_equal ["foo.md"], units.map(&:path)
      md = orch.convert_unit(units[0])
      assert_match(/\Ainclude:\n  - Enumerable\n/, md[/include:.*?(?=---)/m])
    end
  end

  def test_units_inline_entities_inherit_library_gate
    # gated ライブラリ（until 3.1）のインライン・エンティティは until を継承する。
    # 概要部が無くてもライブラリ自体が発見から消えないよう front matter だけの
    # 概要ユニットを合成する
    with_orchestrator do |orch|
      rrd = "= class G < Object\ninclude Enumerable\n\nG。\n\n= class G::E < StandardError\nE。\n"
      units = orch.units("gated.rd", rrd)
      assert_equal ["gated.md", "gated/G.md", "gated/G__E.md"], units.map(&:path)
      assert_equal "---\ntype: library\nuntil: \"3.1\"\n---\n", orch.convert_unit(units[0])
      assert_equal({ "library" => "gated", "until" => "3.1" }, units[1].front_matter)
    end
  end
end

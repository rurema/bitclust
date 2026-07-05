# frozen_string_literal: true

require 'test/unit'
require 'tmpdir'
require 'fileutils'

require 'bitclust/markdown_bridge'

# MarkdownBridge: md ツリー → 旧形式の rd ツリー（LIBRARIES + .rd）を生成する。
# 既存の update 機構（LIBRARIES → RRDParser/Preprocessor）をそのまま使って
# md ツリーから DB を組み立てるためのブリッジ。
#
# テストリスト:
# [x] LIBRARIES を発見結果から再生成（名前順、版ゲート付きライブラリは #@ で包む）
# [x] ライブラリ .rd = 変換済み本文 + メンバーへの #@include（lib のディレクトリ相対）
# [x] メンバー rd = 変換済み本文を front matter の since/until で #@ ラップ
# [x] 断片は拡張子なしで emit、include ターゲットは emit 名へ書き換え
# [x] dual ファイル（lib + インライン・エンティティ）はゲートラップしない（LIBRARIES 側で処理）
class TestMarkdownBridge < Test::Unit::TestCase
  FILES = {
    "foo.md" => "---\ntype: library\ncategory: Cat\n---\n概要。\n\n\#@include(frag)\n",
    "foo/A.md" => "---\nlibrary: foo\nsince: \"3.2\"\n---\n# class A < Object\n\nA。\n",
    "foo/B.md" => "---\nlibrary: foo\n---\n# class B < Object\nB。\n",
    "frag.md" => "断片。\n",
    "gated.md" => "---\ntype: library\nuntil: \"3.1\"\n---\ngated 概要。\n",
    "bar/baz.md" => "---\ntype: library\n---\nbaz 概要。\n",
    "bar/C.md" => "---\nlibrary: bar/baz\n---\n# class C < Object\nC。\n",
    "dual.md" => "---\ntype: library\n---\n# class Dual < Object\nDual。\n",
  }.freeze

  def build
    Dir.mktmpdir do |md|
      FILES.each do |path, content|
        full = File.join(md, path)
        FileUtils.mkdir_p(File.dirname(full))
        File.write(full, content)
      end
      Dir.mktmpdir do |out|
        BitClust::MarkdownBridge.build(md, out)
        result = {}
        Dir.glob('**/*', base: out).each do |f|
          full = File.join(out, f)
          result[f] = File.read(full) if File.file?(full)
        end
        return result
      end
    end
  end

  def test_libraries_manifest
    out = build
    assert_equal "bar/baz\ndual\nfoo\n\#@until 3.1\ngated\n\#@end\n", out["LIBRARIES"]
  end

  def test_source_map_maps_emitted_to_md
    # source_location の md パスへの再マップ用（emit 相対 → md 相対）
    Dir.mktmpdir do |md|
      FILES.each do |path, content|
        full = File.join(md, path)
        FileUtils.mkdir_p(File.dirname(full))
        File.write(full, content)
      end
      Dir.mktmpdir do |out|
        bridge = BitClust::MarkdownBridge.build(md, out)
        assert_equal "foo.md", bridge.source_map["foo.rd"]
        assert_equal "foo/A.md", bridge.source_map["foo/A"]
        assert_equal "frag.md", bridge.source_map["frag"]
        return
      end
    end
  end

  def test_build_doc_returns_source_map
    Dir.mktmpdir do |md|
      File.write(File.join(md, "index.md"), "# はじめに\n\n本文。\n")
      Dir.mktmpdir do |out|
        map = BitClust::MarkdownBridge.build_doc(md, File.join(out, "doc"))
        assert_equal({ "index.rd" => "index.md" }, map)
        return
      end
    end
  end

  def test_library_rd_with_member_includes
    out = build
    assert_equal "category Cat\n\n概要。\n\n\#@include(frag)\n\n" \
                 "\#@include(foo/A)\n\#@include(foo/B)\n", out["foo.rd"]
    assert_equal "baz 概要。\n\n\#@include(C)\n", out["bar/baz.rd"]
  end

  def test_member_rd_with_gate_wrapper
    out = build
    assert_equal "\#@since 3.2\n= class A < Object\n\nA。\n\#@end\n", out["foo/A"]
    assert_equal "= class B < Object\nB。\n", out["foo/B"]
  end

  def test_fragment_is_emitted_without_extension
    out = build
    assert_equal "断片。\n", out["frag"]
  end

  def test_dual_file_keeps_inline_entities_without_wrapper
    out = build
    assert_equal "= class Dual < Object\nDual。\n", out["dual.rd"]
  end

  def test_build_doc_emits_local_fragments_without_extension
    # spec/regexp.rd → #@include(regexp19): doc 内ローカル断片は拡張子なしで emit
    # （copy_doc は **/*.rd だけをページとして読むため、断片に .rd を付けると
    # ページとして二重取り込みされる上、include の解決も切れる）
    Dir.mktmpdir do |md|
      FileUtils.mkdir_p(File.join(md, "spec"))
      File.write(File.join(md, "spec/regexp.md"), "# 正規表現\n\n\#@include(regexp19)\n")
      File.write(File.join(md, "spec/regexp19.md"), "断片。\n")
      Dir.mktmpdir do |out|
        BitClust::MarkdownBridge.build_doc(md, File.join(out, "doc"))
        assert_equal "= 正規表現\n\n\#@include(regexp19)\n",
          File.read(File.join(out, "doc/spec/regexp.rd"))
        assert_equal "断片。\n", File.read(File.join(out, "doc/spec/regexp19"))
        return
      end
    end
  end

  def test_build_doc_converts_and_rewrites_cross_tree_includes
    # manual/doc の md → ブリッジの doc/*.rd。クロスツリー include は
    # 旧レイアウト（../api/src/）へ戻す
    Dir.mktmpdir do |md|
      FileUtils.mkdir_p(File.join(md, "spec"))
      File.write(File.join(md, "pack_template.md"),
        "# pack テンプレート\n\n\#@include(../api/_builtin/pack-template)\n")
      File.write(File.join(md, "spec/intro.md"), "# はじめに\n\n本文。\n")
      Dir.mktmpdir do |out|
        BitClust::MarkdownBridge.build_doc(md, File.join(out, "doc"))
        assert_equal "= pack テンプレート\n\n\#@include(../api/src/_builtin/pack-template)\n",
          File.read(File.join(out, "doc/pack_template.rd"))
        assert_equal "= はじめに\n\n本文。\n", File.read(File.join(out, "doc/spec/intro.rd"))
        return
      end
    end
  end

  def test_reopen_members_are_included_last
    # json.rd/rake.rd: reopen が dynamic include する module は先に定義されている
    # 必要がある（RRDParser の検証）。reopen/redefine だけのファイルは後ろに並べる
    files = {
      "j.md" => "---\ntype: library\n---\nj 概要。\n",
      "j/Array.md" => "---\nlibrary: j\n---\n# reopen Array\n",
      "j/Gen.md" => "---\nlibrary: j\n---\n# module Gen\n",
    }
    Dir.mktmpdir do |md|
      files.each do |path, content|
        full = File.join(md, path)
        FileUtils.mkdir_p(File.dirname(full))
        File.write(full, content)
      end
      Dir.mktmpdir do |out|
        BitClust::MarkdownBridge.build(md, out)
        assert_equal "j 概要。\n\n\#@include(j/Gen)\n\#@include(j/Array)\n",
          File.read(File.join(out, "j.rd"))
        return
      end
    end
  end
end

# frozen_string_literal: true

require 'test/unit'
require 'tmpdir'
require 'fileutils'

require 'bitclust/markdown_tree'

# MarkdownTree: 新パイプラインのファイル発見（MARKUP_SPEC §1.1）。
# refm/api/src/**/*.md を glob し、front matter と H1 から
# エンティティ / ライブラリ / 共有断片 に分類する。LIBRARIES は使わない。
#
# 検証（ビルド警告）:
# - 孤児: エンティティ H1 も type: library も持たず、どの #@include からも参照されない
# - library の無いエンティティ（スコープ外サルベージ分は許容リストで扱う）
# - 未知の library を指すエンティティ
# - 関係リント: マルチエンティティファイルに front matter の関係キー、
#   または本文 H1 直後の関係行があれば警告（関係は front matter が唯一の記述場所）
# - #@include 先の欠損
#
# テストリスト:
# [x] type: library → ライブラリ（名前 = パスから .md を除いたもの）
# [x] エンティティ H1 → エンティティ（名前・library を読む）
# [x] 両方持つ dual ファイル（pathname 型）は両方に数える
# [x] どちらでもない + 参照あり → 断片
# [x] どちらでもない + 参照なし → 孤児警告
# [x] コードフェンス内の「# class」風の行は H1 に数えない
# [x] #@include の解決: target / target.md / target の .rd → .md
# [x] 断片からの #@include も参照として辿る
# [x] library なしエンティティ → 警告
# [x] 未知 library 参照 → 警告
# [x] マルチエンティティ + front matter 関係キー → リント警告
# [x] マルチエンティティ + 本文 H1 直後の関係行 → リント警告
# [x] include 先欠損 → 警告
class TestMarkdownTree < Test::Unit::TestCase
  def scan(files)
    Dir.mktmpdir do |dir|
      files.each do |path, content|
        full = File.join(dir, path)
        FileUtils.mkdir_p(File.dirname(full))
        File.write(full, content)
      end
      return BitClust::MarkdownTree.scan(dir)
    end
  end

  LIB = "---\ntype: library\ncategory: Cat\n---\n概要。\n"

  def test_library_file
    tree = scan("foo.md" => LIB)
    assert_equal ["foo"], tree.libraries.keys
  end

  def test_entity_file
    tree = scan(
      "foo.md" => LIB,
      "foo/Bar.md" => "---\nlibrary: foo\n---\n# class Bar < Object\n\n説明。\n"
    )
    assert_equal ["Bar"], tree.entities["foo/Bar.md"][:names]
    assert_equal "foo", tree.entities["foo/Bar.md"][:library]
    assert_equal [], tree.warnings
  end

  def test_dual_library_entity_file
    tree = scan("foo.md" => "---\ntype: library\n---\n# class Foo < Object\n説明。\n")
    assert_equal ["foo"], tree.libraries.keys
    assert_equal ["Foo"], tree.entities["foo.md"][:names]
  end

  def test_fragment_and_orphan
    tree = scan(
      "foo.md" => LIB + "\#@include(frag)\n",
      "foo/orphan.md" => "誰からも参照されない断片。\n",
      "frag.md" => "参照される断片。\n"
    )
    assert_equal ["frag.md"], tree.fragments
    assert tree.warnings.any? { |w| w.include?("orphan") && w.include?("foo/orphan.md") },
      tree.warnings.inspect
  end

  def test_code_fence_h1_is_not_entity
    md = "---\nlibrary: foo\n---\n# class Bar < Object\n\n`````\n# class Fake < Object\n`````\n"
    tree = scan("foo.md" => LIB, "foo/Bar.md" => md)
    assert_equal ["Bar"], tree.entities["foo/Bar.md"][:names]
  end

  def test_include_resolution_variants
    tree = scan(
      "foo.md" => LIB + "\#@include(frag)\n\#@include(other.rd)\n\#@include(third.md)\n",
      "frag.md" => "断片1。\n",
      "other.md" => "断片2。\n",
      "third.md" => "断片3。\n"
    )
    assert_equal ["frag.md", "other.md", "third.md"], tree.fragments.sort
    assert_equal [], tree.warnings
  end

  def test_fragment_chain_is_followed
    tree = scan(
      "foo.md" => LIB + "\#@include(a)\n",
      "a.md" => "断片A。\n\#@include(b)\n",
      "b.md" => "断片B。\n"
    )
    assert_equal ["a.md", "b.md"], tree.fragments.sort
    assert_equal [], tree.warnings
  end

  def test_referenced_file_without_front_matter_is_fragment_even_with_h1
    # fiddle/2.0/types.rd 型: エンティティ H1 を含む断片が include 参照される
    # （transclusion で取り込まれるので単独エンティティとしては数えない）
    tree = scan(
      "foo.md" => LIB + "\#@include(part)\n",
      "part.md" => "断片。\n\n# reopen Fiddle\n### def win_types\n"
    )
    assert_equal ["part.md"], tree.fragments
    assert_false tree.entities.key?("part.md")
    assert_equal [], tree.warnings
  end

  def test_entity_kinds_are_recorded
    tree = scan(
      "foo.md" => LIB,
      "foo/Bar.md" => "---\nlibrary: foo\n---\n# class Bar < Object\n\n# reopen Kernel\n"
    )
    assert_equal [%w[class Bar], %w[reopen Kernel]], tree.entities["foo/Bar.md"][:kinds]
  end

  def test_entity_without_library_warns
    tree = scan("foo.md" => LIB, "Dead.md" => "# class Dead < Object\n説明。\n")
    assert tree.warnings.any? { |w| w.include?("no library") && w.include?("Dead.md") },
      tree.warnings.inspect
  end

  def test_unknown_library_reference_warns
    tree = scan("Bar.md" => "---\nlibrary: ghost\n---\n# class Bar < Object\n")
    assert tree.warnings.any? { |w| w.include?("unknown library") && w.include?("ghost") },
      tree.warnings.inspect
  end

  def test_multi_entity_with_front_matter_relations_lints
    md = "---\nlibrary: foo\ninclude:\n  - Enumerable\n---\n# class A < Object\n\n# class B < Object\n"
    tree = scan("foo.md" => LIB, "foo/AB.md" => md)
    assert tree.warnings.any? { |w| w.include?("relation") && w.include?("foo/AB.md") },
      tree.warnings.inspect
  end

  def test_multi_entity_with_body_relations_lints
    md = "---\nlibrary: foo\n---\n# class A < Object\ninclude Enumerable\n\n# class B < Object\n"
    tree = scan("foo.md" => LIB, "foo/AB.md" => md)
    assert tree.warnings.any? { |w| w.include?("relation") && w.include?("foo/AB.md") },
      tree.warnings.inspect
  end

  def test_single_entity_body_relation_also_lints
    # O3 後の正しい形では本文関係行は存在しないはず（単一でも警告）
    md = "---\nlibrary: foo\n---\n# class A < Object\ninclude Enumerable\n"
    tree = scan("foo.md" => LIB, "foo/A.md" => md)
    assert tree.warnings.any? { |w| w.include?("relation") && w.include?("foo/A.md") },
      tree.warnings.inspect
  end

  def test_missing_include_target_warns
    tree = scan("foo.md" => LIB + "\#@include(nothing)\n")
    assert tree.warnings.any? { |w| w.include?("include target not found") },
      tree.warnings.inspect
  end
end

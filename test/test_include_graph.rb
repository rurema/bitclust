# frozen_string_literal: true

require 'test/unit'
require 'tmpdir'
require 'fileutils'

require 'bitclust/include_graph'

# IncludeGraph: doctree の #@include グラフを版ゲート付きで解析する faithful 層。
# スコープ（[3.0,4.2) 等）は適用せず、生の全所属・全ゲートを収集する。
# スコープ適用は IncludeGraph::Scope（別テストセクション）が担う。
#
# テストリスト:
# [x] LIBRARIES の 1行1ライブラリ → root (<name>.rd) から grouping メンバーを収集
# [x] 分類: 最初の非空・非#@行が = class|module|object|reopen|redefine → grouping、他 → fragment
# [x] パス解決: include 元ディレクトリ相対、target そのまま → 無ければ target.rd
# [x] LIBRARIES の重複エントリは dedupe
# [x] include サイトの #@since/#@until → membership conditions
# [x] #@else で最内条件を反転（since↔until、同一バージョン）
# [x] #@if は版制約なしの条件として記録（#@else でも版制約なしのまま）
# [x] ネストした条件は全て積む、#@end で pop
# [x] LIBRARIES 内の版ゲートはそのライブラリの全 membership の先頭条件になる
# [x] 再帰: grouping メンバーが include する grouping にも経路の条件を継承した membership
# [x] 多重所属: 複数経路から include される grouping は memberships 複数（生のまま保持）
# [x] 同一 (library, conditions) の重複 membership は dedupe
# [x] 循環 include で無限ループしない（warning 記録）
# [x] 存在しない include 対象 → warning 記録（エラーにしない）
# [x] interval: conditions → [lo, hi)（since は max、until は min、:if は無視）
# [x] Scope#cover?: 範囲 [lo, hi) と交差するか
# [x] Scope#gate: front matter に書く since/until（スコープ境界内のみ、範囲外は省略）
class TestIncludeGraph < Test::Unit::TestCase
  def analyze(files)
    Dir.mktmpdir do |dir|
      files.each do |path, content|
        full = File.join(dir, path)
        FileUtils.mkdir_p(File.dirname(full))
        File.write(full, content)
      end
      return BitClust::IncludeGraph.analyze(dir)
    end
  end

  def membership(library, conditions = [])
    BitClust::IncludeGraph::Membership.new(
      library,
      conditions.map { |kind, version| BitClust::IncludeGraph::Condition.new(kind, version) }
    )
  end

  # ---- roots と分類 ----

  def test_simple_grouping_membership
    graph = analyze(
      "LIBRARIES" => "foo\n",
      "foo.rd"    => "\#@include(foo/Bar)\n",
      "foo/Bar"   => "= class Bar < Object\n"
    )
    assert_equal [membership("foo")], graph.memberships("foo/Bar")
  end

  def test_fragment_classification
    graph = analyze(
      "LIBRARIES" => "foo\n",
      "foo.rd"    => "\#@include(foo/Bar)\n\#@include(foo/frag)\n",
      "foo/Bar"   => "= class Bar < Object\n",
      "foo/frag"  => "ただの散文断片。\n"
    )
    assert_equal ["foo/Bar"], graph.groupings.keys
    assert_equal ["foo/frag"], graph.fragments
  end

  def test_classification_skips_blank_and_directive_lines
    graph = analyze(
      "LIBRARIES" => "foo\n",
      "foo.rd"    => "\#@include(foo/Bar)\n",
      "foo/Bar"   => "\n\#@since 1.9.1\n= reopen Kernel\n\#@end\n"
    )
    assert_equal ["foo/Bar"], graph.groupings.keys
  end

  def test_include_resolves_with_rd_fallback
    graph = analyze(
      "LIBRARIES" => "foo\n",
      "foo.rd"    => "\#@include(foo/Bar)\n",
      "foo/Bar.rd" => "= class Bar < Object\n"
    )
    assert_equal [membership("foo")], graph.memberships("foo/Bar.rd")
  end

  def test_include_resolves_relative_to_including_file
    graph = analyze(
      "LIBRARIES"   => "foo/sub\n",
      "foo/sub.rd"  => "\#@include(Bar)\n",
      "foo/Bar"     => "= class Bar < Object\n"
    )
    assert_equal [membership("foo/sub")], graph.memberships("foo/Bar")
  end

  def test_libraries_skips_preprocessor_comment_lines
    # LIBRARIES には「#@# json/add/rails.rd」のようなコメントアウト行がある
    graph = analyze(
      "LIBRARIES" => "foo\n\#@# ghost\n",
      "foo.rd"    => "\#@include(foo/Bar)\n",
      "foo/Bar"   => "= class Bar < Object\n"
    )
    assert_equal [], graph.warnings
    assert_equal [membership("foo")], graph.memberships("foo/Bar")
  end

  def test_duplicate_libraries_entries_are_deduped
    graph = analyze(
      "LIBRARIES" => "foo\nfoo\n",
      "foo.rd"    => "\#@include(foo/Bar)\n",
      "foo/Bar"   => "= class Bar < Object\n"
    )
    assert_equal [membership("foo")], graph.memberships("foo/Bar")
  end

  # ---- 版ゲート ----

  def test_include_under_since_gate
    graph = analyze(
      "LIBRARIES" => "foo\n",
      "foo.rd"    => "\#@since 3.2\n\#@include(foo/Bar)\n\#@end\n",
      "foo/Bar"   => "= class Bar < Object\n"
    )
    assert_equal [membership("foo", [[:since, "3.2"]])], graph.memberships("foo/Bar")
  end

  def test_include_in_else_branch_inverts_since
    # thread.rd パターン: #@since 2.3.0 ... #@else [include群] #@end → 実効 until 2.3.0
    graph = analyze(
      "LIBRARIES" => "foo\n",
      "foo.rd"    => "\#@since 2.3.0\ntext\n\#@else\n\#@include(foo/Bar)\n\#@end\n",
      "foo/Bar"   => "= class Bar < Object\n"
    )
    assert_equal [membership("foo", [[:until, "2.3.0"]])], graph.memberships("foo/Bar")
  end

  def test_include_in_else_branch_inverts_until
    graph = analyze(
      "LIBRARIES" => "foo\n",
      "foo.rd"    => "\#@until 1.9.1\ntext\n\#@else\n\#@include(foo/Bar)\n\#@end\n",
      "foo/Bar"   => "= class Bar < Object\n"
    )
    assert_equal [membership("foo", [[:since, "1.9.1"]])], graph.memberships("foo/Bar")
  end

  def test_include_under_if_gate_records_condition_without_version_bound
    graph = analyze(
      "LIBRARIES" => "foo\n",
      "foo.rd"    => "\#@if (version < \"1.8.2\")\n\#@include(foo/Bar)\n\#@end\n",
      "foo/Bar"   => "= class Bar < Object\n"
    )
    assert_equal [membership("foo", [[:if, '(version < "1.8.2")']])],
      graph.memberships("foo/Bar")
  end

  def test_include_in_else_branch_of_if_records_negation
    graph = analyze(
      "LIBRARIES" => "foo\n",
      "foo.rd"    => "\#@if (version < \"1.8.2\")\ntext\n\#@else\n\#@include(foo/Bar)\n\#@end\n",
      "foo/Bar"   => "= class Bar < Object\n"
    )
    assert_equal [membership("foo", [[:if, '!((version < "1.8.2"))']])],
      graph.memberships("foo/Bar")
  end

  def test_nested_gates_accumulate_and_end_pops
    src = <<~RRD
      \#@since 2.0.0
      \#@until 3.0
      \#@include(foo/Bar)
      \#@end
      \#@include(foo/Baz)
      \#@end
      \#@include(foo/Qux)
    RRD
    graph = analyze(
      "LIBRARIES" => "foo\n",
      "foo.rd"    => src,
      "foo/Bar"   => "= class Bar < Object\n",
      "foo/Baz"   => "= class Baz < Object\n",
      "foo/Qux"   => "= class Qux < Object\n"
    )
    assert_equal [membership("foo", [[:since, "2.0.0"], [:until, "3.0"]])],
      graph.memberships("foo/Bar")
    assert_equal [membership("foo", [[:since, "2.0.0"]])], graph.memberships("foo/Baz")
    assert_equal [membership("foo")], graph.memberships("foo/Qux")
  end

  def test_libraries_gate_prefixes_membership_conditions
    # LIBRARIES の cmath は #@until 2.7.0 に包まれている実例に対応
    graph = analyze(
      "LIBRARIES" => "\#@until 2.7.0\nfoo\n\#@end\nother\n",
      "foo.rd"    => "\#@since 1.9.1\n\#@include(foo/Bar)\n\#@end\n",
      "other.rd"  => "text\n",
      "foo/Bar"   => "= class Bar < Object\n"
    )
    assert_equal [membership("foo", [[:until, "2.7.0"], [:since, "1.9.1"]])],
      graph.memberships("foo/Bar")
  end

  # ---- 再帰と多重所属 ----

  def test_nested_grouping_inherits_path_conditions
    # rdoc/context.rd → RDoc__Context のような2段 grouping
    graph = analyze(
      "LIBRARIES"  => "foo\n",
      "foo.rd"     => "\#@since 2.0.0\n\#@include(foo/Bar)\n\#@end\n",
      "foo/Bar"    => "= class Bar < Object\n\#@until 3.0\n\#@include(Baz)\n\#@end\n",
      "foo/Baz"    => "= class Baz < Object\n"
    )
    assert_equal [membership("foo", [[:since, "2.0.0"], [:until, "3.0"]])],
      graph.memberships("foo/Baz")
  end

  def test_fragment_include_from_member
    # _builtin/Array → pack-template のような断片 include
    graph = analyze(
      "LIBRARIES" => "foo\n",
      "foo.rd"    => "\#@include(foo/Bar)\n",
      "foo/Bar"   => "= class Bar < Object\n\#@include(frag)\n",
      "foo/frag"  => "断片テキスト。\n"
    )
    assert_equal ["foo/frag"], graph.fragments
    assert_equal [], graph.memberships("foo/frag")
  end

  def test_multiple_memberships_are_kept_raw
    # cgi/core.rd が util.rd（cgi/util のルート）を #@until 内で include する実例に対応
    graph = analyze(
      "LIBRARIES" => "foo\nbar\n",
      "foo.rd"    => "\#@include(shared/Thing)\n",
      "bar.rd"    => "\#@until 1.9.1\n\#@include(shared/Thing)\n\#@end\n",
      "shared/Thing" => "= class Thing < Object\n"
    )
    assert_equal [
      membership("foo"),
      membership("bar", [[:until, "1.9.1"]]),
    ], graph.memberships("shared/Thing")
  end

  def test_identical_memberships_are_deduped
    # _builtin/Data → Data.attention 9回のような同一 include の繰り返し（grouping 版）
    graph = analyze(
      "LIBRARIES" => "foo\n",
      "foo.rd"    => "\#@include(foo/Bar)\n\#@include(foo/Bar)\n",
      "foo/Bar"   => "= class Bar < Object\n"
    )
    assert_equal [membership("foo")], graph.memberships("foo/Bar")
  end

  def test_entity_h1_without_space_is_grouping
    # RRDParser は /\A=[^=]/ で H1 を認識するため「=class Encoding」も有効
    # （実データ: _builtin/Encoding, _builtin/Encoding__Converter）
    graph = analyze(
      "LIBRARIES" => "foo\n",
      "foo.rd"    => "\#@include(foo/Bar)\n",
      "foo/Bar"   => "=class Bar < Object\n"
    )
    assert_equal [membership("foo")], graph.memberships("foo/Bar")
  end

  def test_membership_propagates_through_fragment_chain
    # fiddle.rd → fiddle/2.0/fiddle.rd（散文開始=fragment）→ Fiddle（grouping）の
    # transclusion チェーン。fragment を経由しても所属と経路条件は伝播する
    graph = analyze(
      "LIBRARIES"    => "foo\n",
      "foo.rd"       => "\#@until 2.0.0\n\#@include(foo/1.9/frag.rd)\n\#@else\n\#@include(foo/2.0/frag.rd)\n\#@end\n",
      "foo/1.9/frag.rd" => "散文。\n\#@include(Bar)\n",
      "foo/2.0/frag.rd" => "散文。\n\#@include(Bar)\n",
      "foo/1.9/Bar"  => "= class Bar < Object\n",
      "foo/2.0/Bar"  => "= class Bar < Object\n"
    )
    assert_equal [membership("foo", [[:until, "2.0.0"]])], graph.memberships("foo/1.9/Bar")
    assert_equal [membership("foo", [[:since, "2.0.0"]])], graph.memberships("foo/2.0/Bar")
    assert_equal ["foo/1.9/frag.rd", "foo/2.0/frag.rd"], graph.fragments
  end

  def test_include_with_dotdot_path_is_normalized
    # rdoc/parsers/parse_c.rd の #@include(../RDoc__KNOWN_CLASSES) に対応。
    # 正規化しないと同一ファイルが別キーで二重登録される
    graph = analyze(
      "LIBRARIES" => "foo\n",
      "foo.rd"    => "\#@include(foo/sub/Baz)\n\#@include(foo/Bar)\n",
      "foo/sub/Baz" => "= class Baz < Object\n\#@include(../Bar)\n",
      "foo/Bar"   => "= class Bar < Object\n"
    )
    assert_equal ["foo/Bar", "foo/sub/Baz"], graph.groupings.keys
    assert_equal [membership("foo")], graph.memberships("foo/Bar")
  end

  def test_include_cycle_terminates_with_warning
    graph = analyze(
      "LIBRARIES" => "foo\n",
      "foo.rd"    => "\#@include(foo/Bar)\n",
      "foo/Bar"   => "= class Bar < Object\n\#@include(Baz)\n",
      "foo/Baz"   => "= class Baz < Object\n\#@include(Bar)\n"
    )
    assert graph.warnings.any? { |w| w.include?("cycle") },
      "expected cycle warning, got: #{graph.warnings.inspect}"
  end

  def test_missing_include_target_records_warning
    graph = analyze(
      "LIBRARIES" => "foo\n",
      "foo.rd"    => "\#@include(foo/Nothing)\n"
    )
    assert_equal ["include target not found: foo/Nothing (from foo.rd)"], graph.warnings
  end

  def test_missing_library_root_records_warning
    graph = analyze("LIBRARIES" => "ghost\n")
    assert_equal ["library root not found: ghost.rd"], graph.warnings
  end

  def test_samplecode_block_end_does_not_pop_version_gate
    # #@samplecode ブロックも #@end で閉じるため、pop の対応を取る必要がある
    src = <<~RRD
      \#@since 3.2
      \#@samplecode 例
      p 1
      \#@end
      \#@include(foo/Bar)
      \#@end
      \#@include(foo/Baz)
    RRD
    graph = analyze(
      "LIBRARIES" => "foo\n",
      "foo.rd"    => src,
      "foo/Bar"   => "= class Bar < Object\n",
      "foo/Baz"   => "= class Baz < Object\n"
    )
    assert_equal [membership("foo", [[:since, "3.2"]])], graph.memberships("foo/Bar")
    assert_equal [membership("foo")], graph.memberships("foo/Baz")
  end

  def test_include_allows_space_before_paren
    # Preprocessor は #@include\s*\( を許容する
    graph = analyze(
      "LIBRARIES" => "foo\n",
      "foo.rd"    => "\#@include (foo/Bar)\n",
      "foo/Bar"   => "= class Bar < Object\n"
    )
    assert_equal [membership("foo")], graph.memberships("foo/Bar")
  end

  # ---- interval とスコープ適用 ----

  def conditions(*pairs)
    pairs.map { |kind, version| BitClust::IncludeGraph::Condition.new(kind, version) }
  end

  def interval(*pairs)
    BitClust::IncludeGraph.interval(conditions(*pairs))
  end

  def test_interval_unconstrained
    assert_equal [nil, nil], interval
  end

  def test_interval_since_takes_max_and_until_takes_min
    assert_equal [Gem::Version.new("2.3.0"), nil], interval([:since, "2.3.0"])
    assert_equal [nil, Gem::Version.new("2.7.0")], interval([:until, "2.7.0"])
    assert_equal [Gem::Version.new("2.3.0"), Gem::Version.new("3.0")],
      interval([:since, "1.9.1"], [:since, "2.3.0"], [:until, "3.1"], [:until, "3.0"])
  end

  def test_interval_ignores_if_conditions
    assert_equal [Gem::Version.new("3.2"), nil],
      interval([:if, '(version > "1.8.2")'], [:since, "3.2"])
  end

  def test_scope_cover
    scope = BitClust::IncludeGraph::Scope.new("3.0", "4.2")
    assert_true  scope.cover?(conditions)                                       # 無条件
    assert_true  scope.cover?(conditions([:since, "3.2"]))                      # Data
    assert_true  scope.cover?(conditions([:since, "2.3.0"]))                    # 下限跨ぎ
    assert_true  scope.cover?(conditions([:until, "3.1"]))                      # 上限側交差
    assert_false scope.cover?(conditions([:until, "2.3.0"]))                    # thread 旧所属
    assert_false scope.cover?(conditions([:until, "3.0"]))                      # 境界: [_,3.0) は交差なし
    assert_false scope.cover?(conditions([:since, "4.2"]))                      # 境界: [4.2,_) は交差なし
    assert_false scope.cover?(conditions([:since, "3.5"], [:until, "3.2"]))     # 空区間
    assert_true  scope.cover?(conditions([:if, 'x']))                           # :if は制約なし扱い
  end

  def test_scope_gate_keeps_only_bounds_inside_scope
    scope = BitClust::IncludeGraph::Scope.new("3.0", "4.2")
    assert_equal({}, scope.gate(conditions))
    assert_equal({ since: "3.2" }, scope.gate(conditions([:since, "3.2"])))
    assert_equal({}, scope.gate(conditions([:since, "2.3.0"])))                 # 下限以下は省略
    assert_equal({}, scope.gate(conditions([:since, "3.0"])))                   # 下限ちょうども省略
    assert_equal({ until: "4.0" }, scope.gate(conditions([:until, "4.0"])))
    assert_equal({ since: "3.2", until: "4.0" },
      scope.gate(conditions([:since, "3.2"], [:until, "4.0"])))
    assert_nil scope.gate(conditions([:until, "2.3.0"]))                        # スコープ外
  end

  def test_scope_gate_preserves_original_version_spelling
    scope = BitClust::IncludeGraph::Scope.new("3.0", "4.2")
    assert_equal({ since: "3.2.0" }, scope.gate(conditions([:since, "3.2.0"])))
  end

  # ---- front_matter_map: メンバーへの注入値（スコープ適用済み）----

  def scope30_42
    BitClust::IncludeGraph::Scope.new("3.0", "4.2")
  end

  def test_front_matter_map_simple_membership
    graph = analyze(
      "LIBRARIES" => "foo\n",
      "foo.rd"    => "\#@include(foo/Bar)\n",
      "foo/Bar"   => "= class Bar < Object\n"
    )
    assert_equal({ "foo/Bar" => { "library" => "foo" } }, graph.front_matter_map(scope30_42))
  end

  def test_front_matter_map_with_structural_gate
    graph = analyze(
      "LIBRARIES" => "foo\n",
      "foo.rd"    => "\#@since 3.2\n\#@include(foo/Bar)\n\#@end\n",
      "foo/Bar"   => "= class Bar < Object\n"
    )
    assert_equal({ "foo/Bar" => { "library" => "foo", "since" => "3.2" } },
      graph.front_matter_map(scope30_42))
  end

  def test_front_matter_map_excludes_out_of_scope_members
    graph = analyze(
      "LIBRARIES" => "foo\n",
      "foo.rd"    => "\#@until 2.4.0\n\#@include(foo/Bar)\n\#@end\n",
      "foo/Bar"   => "= class Bar < Object\n"
    )
    assert_equal({}, graph.front_matter_map(scope30_42))
  end

  def test_front_matter_map_skips_multi_library_membership_with_warning
    graph = analyze(
      "LIBRARIES" => "foo\nbar\n",
      "foo.rd"    => "\#@include(shared/Thing)\n",
      "bar.rd"    => "\#@include(shared/Thing)\n",
      "shared/Thing" => "= class Thing < Object\n"
    )
    assert_equal({}, graph.front_matter_map(scope30_42))
    assert graph.warnings.any? { |w| w.include?("multi-membership") },
      "expected multi-membership warning, got: #{graph.warnings.inspect}"
  end

  def test_front_matter_map_takes_interval_hull_within_same_library
    # 同一ライブラリから複数サイトで include される場合、エンティティは
    # いずれかのサイトが有効なら存在する → ゲートは区間の hull（弱い方）を取る
    graph = analyze(
      "LIBRARIES" => "foo\n",
      "foo.rd"    => "\#@since 3.2\n\#@include(foo/Bar)\n\#@end\n" \
                     "\#@since 3.1\n\#@include(foo/Bar)\n\#@end\n",
      "foo/Bar"   => "= class Bar < Object\n"
    )
    assert_equal({ "foo/Bar" => { "library" => "foo", "since" => "3.1" } },
      graph.front_matter_map(scope30_42))
  end

  def test_front_matter_map_unconditional_site_wins_over_gated_site
    graph = analyze(
      "LIBRARIES" => "foo\n",
      "foo.rd"    => "\#@include(foo/Bar)\n\#@since 3.2\n\#@include(foo/Bar)\n\#@end\n",
      "foo/Bar"   => "= class Bar < Object\n"
    )
    assert_equal({ "foo/Bar" => { "library" => "foo" } }, graph.front_matter_map(scope30_42))
  end
end

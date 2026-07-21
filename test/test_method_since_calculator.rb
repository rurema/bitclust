# frozen_string_literal: true
require 'test/unit'
require 'bitclust'
require 'bitclust/methoddatabase'
require 'bitclust/method_since_calculator'
require 'tmpdir'
require 'fileutils'

# メソッド名別 since/until の算出(bitclust#132 P2)。
#
# テストリスト:
# [x] フロア(ラダー最古版から存在)のメソッドは since も until も付かない
# [x] #@since ゲート付きメソッドは、追加された版以降の対象すべてで
#     since が付く
# [x] 別名グループ: シグネチャごとに異なるゲートを持てば名前ごとに
#     別の since になる(-@ は 2.0.0、dedup は 3.0)。ゲートが効いて
#     いない版の対象ではその別名自体が存在しない
# [x] #@until ゲート付きメソッドは、消える1つ前の版の対象で until が付き、
#     消えた後の対象にはエントリ自体が存在しない
# [x] インスタンスメソッドとシンゲルトンメソッドは同名でも別キー
# [x] kind=:undefined のエントリは走査で無視される: {: undef} → 実メソッド化
#     したものは実メソッド化した版が since になり、逆に undef 化は削除扱いで
#     前の版の対象に until が付く
# [x] kind=:undefined のエントリには適用でも書き込まない
# [x] ラダーに同じバージョンが重複していれば .new で UserError
# [x] apply は冪等: 2回目は floor_skipped 以外すべて0
# [x] 既に値がある名前は上書きしない(著者値が算出値より優先)
# [x] 対象DBのバージョンがラダーに無ければ apply は UserError
# [x] 統合: `{: since="X"}` 属性行(#132 P4)でパース時に記録された値は
#     算出結果で上書きされない(RD ソース上の明示注記が算出値より優先)
class TestMethodSinceCalculator < Test::Unit::TestCase
  RD = <<~'RD'
    description

    = class MSCTest
    == Instance Methods
    --- old_timer

    説明

    #@since 2.0.0
    --- newmeth

    説明
    #@end

    #@since 3.0
    --- overridden
    {: since="2.5"}

    説明
    #@end

    #@since 2.0.0
    --- -@
    #@since 3.0
    --- dedup
    #@end

    説明
    #@end

    #@until 3.0
    --- legacy

    説明
    #@end

    --- undefmeth
    {: undef}

    説明

    --- undef_then_real
    #@until 2.0.0
    {: undef}
    #@end

    説明

    #@since 2.0.0
    --- real_then_undef
    #@since 3.0
    {: undef}
    #@end

    説明
    #@end

    --- marker

    説明

    == Singleton Methods
    #@since 2.0.0
    --- marker

    説明
    #@end
  RD

  LADDER_VERSIONS = %w[1.8.7 2.0.0 3.0]

  def setup
    @tmpdir = Dir.mktmpdir
    @paths = {}
    LADDER_VERSIONS.each {|v| build_db(v) }
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_floor_method_has_no_since_or_until
    run_calculator('2.0.0')
    run_calculator('3.0')
    assert_nil find_entry('2.0.0', 'i', 'old_timer').since_of('old_timer')
    assert_nil find_entry('2.0.0', 'i', 'old_timer').until_of('old_timer')
    assert_nil find_entry('3.0', 'i', 'old_timer').since_of('old_timer')
    assert_nil find_entry('3.0', 'i', 'old_timer').until_of('old_timer')
  end

  def test_since_gated_method_gets_since_in_every_later_target
    run_calculator('2.0.0')
    run_calculator('3.0')
    assert_equal '2.0.0', find_entry('2.0.0', 'i', 'newmeth').since_of('newmeth')
    assert_equal '2.0.0', find_entry('3.0', 'i', 'newmeth').since_of('newmeth')
  end

  def test_alias_group_since_is_split_by_name
    run_calculator('2.0.0')
    run_calculator('3.0')

    at_2_0_0 = find_entry('2.0.0', 'i', '-@')
    assert_equal ['-@'], at_2_0_0.names
    assert_equal '2.0.0', at_2_0_0.since_of('-@')

    at_3_0 = find_entry('3.0', 'i', '-@')
    assert_equal ['-@', 'dedup'], at_3_0.names.sort
    assert_equal '2.0.0', at_3_0.since_of('-@')
    assert_equal '3.0', at_3_0.since_of('dedup')
  end

  def test_until_gated_method
    run_calculator('2.0.0')
    assert_equal '3.0', find_entry('2.0.0', 'i', 'legacy').until_of('legacy')
    assert_nil find_entry('3.0', 'i', 'legacy')
  end

  def test_singleton_and_instance_method_are_distinct_keys
    run_calculator('2.0.0')
    assert_nil find_entry('2.0.0', 'i', 'marker').since_of('marker')
    assert_equal '2.0.0', find_entry('2.0.0', 's', 'marker').since_of('marker')
  end

  def test_undefined_entries_are_ignored_in_scan
    run_calculator('3.0')
    # 全版 {: undef} の undefmeth は presence ゼロ → 何も書かれない
    e = find_entry('3.0', 'i', 'undefmeth')
    assert_equal :undefined, e.kind
    assert_nil e.since_of('undefmeth')
    assert_nil e.until_of('undefmeth')
    # 1.8.7 では {: undef}(存在しない印)なので presence に数えず、実メソッド化
    # した 2.0.0 が since になる(scan がフィルタしなければ floor 扱いで nil)
    assert_equal '2.0.0',
                 find_entry('3.0', 'i', 'undef_then_real').since_of('undef_then_real')
  end

  def test_undefined_entries_are_ignored_in_apply
    run_calculator('2.0.0')
    run_calculator('3.0')
    # 3.0 で undef 化 → presence は 2.0.0 のみ。2.0.0 の対象では削除扱いで
    # until が付く
    at_2_0_0 = find_entry('2.0.0', 'i', 'real_then_undef')
    assert_equal '2.0.0', at_2_0_0.since_of('real_then_undef')
    assert_equal '3.0', at_2_0_0.until_of('real_then_undef')
    # 3.0 の :undefined エントリ自体には(算出値があっても)書き込まない
    at_3_0 = find_entry('3.0', 'i', 'real_then_undef')
    assert_equal :undefined, at_3_0.kind
    assert_nil at_3_0.since_of('real_then_undef')
    assert_nil at_3_0.until_of('real_then_undef')
  end

  def test_duplicate_version_in_ladder_raises
    dbs = ladder_dbs + [fresh_db('2.0.0')]
    assert_raise(BitClust::UserError) { BitClust::MethodSinceCalculator.new(dbs) }
  end

  def test_apply_is_idempotent
    calc = BitClust::MethodSinceCalculator.new(ladder_dbs)
    calc.scan
    first_stats = calc.apply(fresh_db('2.0.0'))
    second_stats = calc.apply(fresh_db('2.0.0'))

    assert_operator first_stats[:since_filled], :>, 0
    assert_equal 0, second_stats[:since_filled]
    assert_equal 0, second_stats[:until_filled]
    assert_equal 0, second_stats[:entries_updated]
    assert_equal first_stats[:floor_skipped], second_stats[:floor_skipped]
  end

  def test_author_value_takes_precedence_over_computed_value
    pre = fresh_db('3.0')
    entry = pre.get_class('MSCTest').entries.find {|m| m.typechar == 'i' && m.name?('newmeth') } or raise
    entry.fill_since('newmeth', '1.9.9')
    entry.save

    calc = BitClust::MethodSinceCalculator.new(ladder_dbs)
    calc.scan
    calc.apply(fresh_db('3.0'))

    assert_equal '1.9.9', find_entry('3.0', 'i', 'newmeth').since_of('newmeth')
  end

  def test_author_since_attribute_parsed_from_source_survives_apply
    # overridden は #@since 3.0 でゲートされているのでラダー上は 3.0 と算出
    # されるが、RD ソースの {: since="2.5"} がパース時点(update_by_stdlibtree)
    # で既に記録されているため、apply(fill_since は未設定時のみ書く)では
    # 上書きされずそのまま残る
    run_calculator('2.0.0')
    run_calculator('3.0')

    assert_nil find_entry('2.0.0', 'i', 'overridden')
    assert_equal '2.5', find_entry('3.0', 'i', 'overridden').since_of('overridden')
  end

  def test_apply_rejects_target_whose_version_is_not_in_ladder
    build_db('4.0')
    calc = BitClust::MethodSinceCalculator.new(ladder_dbs)
    calc.scan
    assert_raise(BitClust::UserError) { calc.apply(fresh_db('4.0')) }
  end

  private

  def build_db(version)
    root = "#{@tmpdir}/tree-#{version}/refm/api/src"
    FileUtils.mkdir_p("#{root}/_builtin")
    File.write("#{root}/LIBRARIES", "_builtin\n")
    File.write("#{root}/_builtin.rd", RD)
    prefix = "#{@tmpdir}/db-#{version}"
    db = BitClust::MethodDatabase.new(prefix)
    db.init
    db.transaction do
      db.propset('version', version)
      db.propset('encoding', 'utf-8')
    end
    db.transaction do
      db.update_by_stdlibtree(root)
    end
    @paths[version] = prefix
    prefix
  end

  def fresh_db(version)
    BitClust::MethodDatabase.new(@paths[version] || raise("no such db: #{version}"))
  end

  def ladder_dbs
    LADDER_VERSIONS.map {|v| fresh_db(v) }
  end

  def run_calculator(target_version)
    calc = BitClust::MethodSinceCalculator.new(ladder_dbs)
    calc.scan
    calc.apply(fresh_db(target_version))
  end

  def find_entry(version, typechar, name)
    fresh_db(version).get_class('MSCTest').entries.find {|m|
      m.typechar == typechar && m.name?(name)
    }
  end
end

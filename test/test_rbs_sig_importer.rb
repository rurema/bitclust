# frozen_string_literal: true
require 'test/unit'
require 'bitclust'
require 'bitclust/methoddatabase'
require 'bitclust/rbs_sig_importer'
require 'tmpdir'
require 'fileutils'
require 'json'

# RbsSigImporter(RBS シグネチャ表示)。.rbs 群から
# "Class#method"/"Class.method" キー → セグメント行列の対応を作り、
# MethodEntry の rbs_sig property に書き込む。
#
# セグメント行列 = 行(オーバーロードごと)の配列。行は [種別, テキスト] の
# 配列で、種別 "t" は素のテキスト、"c" はクラス/モジュール名(描画側が
# DB に存在すればリンク化する)。行のテキストを連結すると元の型シグネチャ
# 文字列に戻る(往復可能)。
#
# テストリスト:
# [x] instance/singleton メソッドが # / . キーになる
# [x] overload は行ごとに分かれ、テキスト連結で元のシグネチャに戻る
# [x] 型名は ["c", name] セグメントになる(引数・戻り値・ジェネリクスの中も)
# [x] 名前空間付き型名は :: が直前のテキスト側に残る
# [x] def self?. は # と . の両キーに登録される
# [x] alias メンバーは元メソッドのシグネチャを共有する
# [x] attr_reader/attr_writer は name / name= キーになり、型だけの行になる
# [x] lookup: typechar i/s/m で引ける(m は # → . の順)
# [x] lookup: new は Class.new → Class#initialize の順でフォールバック
# [x] lookup: 別名リストの後ろの名前でもヒットする
# [x] lookup: 対応が無ければ nil(定数・特殊変数も nil)
# [x] apply: DB のエントリに rbs_sig(JSON)が書き込まれ、統計が返る
# [x] apply: 対応が無いメソッドには書き込まれない
# [x] apply: 2 回目は無変更(entries_updated=0)
class TestRbsSigImporter < Test::Unit::TestCase
  def setup
    @tmpdir = Dir.mktmpdir
    @sig_dir = File.join(@tmpdir, 'sig')
    FileUtils.mkdir_p(@sig_dir)
    File.write(File.join(@sig_dir, 'foo.rbs'), <<~RBS)
      class Foo
        def initialize: (String) -> void
        def bar: (Integer base) -> String
               | (::Enumerator::Lazy) -> Array[Integer]
        def self.build: () -> Foo
        def self?.mf: () -> bool
        alias car bar
        attr_reader label: String
        attr_writer width: Integer
        def pairs: (hash[Symbol, String]) -> void
      end
    RBS
    @importer = BitClust::RbsSigImporter.new(sig_dirs: [@sig_dir])
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_instance_and_singleton_methods_are_keyed
    sigs = @importer.signatures
    assert sigs.key?('Foo#bar')
    assert sigs.key?('Foo#initialize')
    assert sigs.key?('Foo.build')
    assert_false sigs.key?('Foo#build')
  end

  def test_overload_lines_roundtrip_to_original_signature
    lines = @importer.signatures['Foo#bar']
    assert_equal 2, lines.size
    assert_equal '(Integer base) -> String', join_text(lines[0])
    assert_equal '(::Enumerator::Lazy) -> Array[Integer]', join_text(lines[1])
  end

  def test_type_names_become_class_segments
    lines = @importer.signatures['Foo#bar']
    assert_equal(
      [['t', '('], ['c', 'Integer'], ['t', ' base) -> '], ['c', 'String']],
      lines[0])
  end

  def test_namespace_prefix_stays_in_text_segment
    lines = @importer.signatures['Foo#bar']
    assert_equal(
      [['t', '(::'], ['c', 'Enumerator::Lazy'], ['t', ') -> '],
       ['c', 'Array'], ['t', '['], ['c', 'Integer'], ['t', ']']],
      lines[1])
  end

  # 小文字のエイリアス型(hash 等)自体はテキストのままだが、その
  # ジェネリクス引数の中のクラス名はリンク化候補にする
  def test_alias_type_args_become_class_segments
    lines = @importer.signatures['Foo#pairs']
    assert_equal(
      [['t', '(hash['], ['c', 'Symbol'], ['t', ', '], ['c', 'String'],
       ['t', ']) -> void']],
      lines[0])
  end

  def test_self_question_registers_both_keys
    sigs = @importer.signatures
    assert_equal sigs['Foo#mf'], sigs['Foo.mf']
    assert_equal '() -> bool', join_text(sigs['Foo#mf'][0])
  end

  def test_alias_member_shares_signature
    sigs = @importer.signatures
    assert_equal sigs['Foo#bar'], sigs['Foo#car']
  end

  def test_attr_members
    sigs = @importer.signatures
    assert_equal 'String', join_text(sigs['Foo#label'][0])
    assert_equal 'Integer', join_text(sigs['Foo#width='][0])
    assert_equal [['c', 'String']], sigs['Foo#label'][0]
  end

  def test_lookup_by_typechar
    sigs = @importer.signatures
    assert_equal sigs['Foo#bar'], @importer.lookup('Foo', 'i', ['bar'])
    assert_equal sigs['Foo.build'], @importer.lookup('Foo', 's', ['build'])
    assert_equal sigs['Foo#mf'], @importer.lookup('Foo', 'm', ['mf'])
  end

  def test_lookup_new_falls_back_to_initialize
    assert_equal @importer.signatures['Foo#initialize'],
                 @importer.lookup('Foo', 's', ['new'])
  end

  def test_lookup_tries_every_alias_name
    assert_equal @importer.signatures['Foo#bar'],
                 @importer.lookup('Foo', 'i', ['zzz', 'bar'])
  end

  def test_lookup_misses_return_nil
    assert_nil @importer.lookup('Foo', 'i', ['nope'])
    assert_nil @importer.lookup('Bar', 'i', ['bar'])
    assert_nil @importer.lookup('Foo', 'c', ['BAR'])
    assert_nil @importer.lookup('Foo', 'v', ['$bar'])
  end

  def test_apply_writes_rbs_sig_property
    prefix = build_db('4.0')
    stats = @importer.apply(BitClust::MethodDatabase.new(prefix))

    bar = find_entry(prefix, 'bar')
    assert_equal @importer.signatures['Foo#bar'],
                 JSON.parse(bar.rbs_sig)
    assert_equal 1, stats[:entries_updated]
    assert_equal 1, stats[:sigs_matched]
    assert_equal 1, stats[:methods_missed]
  end

  def test_apply_leaves_unmatched_methods_untouched
    prefix = build_db('4.0')
    @importer.apply(BitClust::MethodDatabase.new(prefix))
    assert_nil find_entry(prefix, 'nope').rbs_signature_segments
  end

  def test_apply_twice_is_idempotent
    prefix = build_db('4.0')
    @importer.apply(BitClust::MethodDatabase.new(prefix))
    stats = @importer.apply(BitClust::MethodDatabase.new(prefix))
    assert_equal 0, stats[:entries_updated]
    assert_equal 1, stats[:sigs_matched]
  end

  private

  def join_text(line)
    line.map {|_kind, text| text }.join
  end

  def build_db(version)
    root = "#{@tmpdir}/tree-#{version}/refm/api/src"
    FileUtils.mkdir_p("#{root}/_builtin")
    File.write("#{root}/LIBRARIES", "_builtin\n")
    File.write("#{root}/_builtin.rd", <<~RD)
      description

      = class Foo < Object
      == Instance Methods
      --- bar(base) -> String

      説明

      --- nope -> nil

      説明
    RD
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
    prefix
  end

  def find_entry(prefix, name)
    db = BitClust::MethodDatabase.new(prefix)
    db.get_class('Foo').entries.find {|m| m.name?(name) }
  end
end

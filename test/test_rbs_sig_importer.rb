# frozen_string_literal: true
require 'test/unit'
require 'bitclust'
require 'bitclust/methoddatabase'
require 'bitclust/rbs_sig_importer'
require 'tmpdir'
require 'fileutils'
require 'json'

# RbsSigImporter(RBS シグネチャ表示)。.rbs 群から
# "Class#method"/"Class.method" キー → オーバーロード配列の対応を作り、
# MethodEntry の rbs_sig property に書き込む。
#
# オーバーロード = {"segments" => 行, "params" => 引数名, "arity" =>
# [最小, 最大|nil], "block" => "req"|"opt"} の Hash(segments 以外は
# チャンク振り分け=RbsOverloadMatcher 用のメタ情報で、無い形式もある)。
# 行は [種別, テキスト] の配列で、種別 "t" は素のテキスト、"c" は
# クラス/モジュール名(描画側が DB に存在すればリンク化する)。行の
# テキストを連結すると元の型シグネチャ文字列に戻る(往復可能)。
#
# テストリスト:
# [x] instance/singleton メソッドが # / . キーになる
# [x] overload はオーバーロードごとに分かれ、テキスト連結で元に戻る
# [x] 型名は ["c", name] セグメントになる(引数・戻り値・ジェネリクスの中も)
# [x] 名前空間付き型名は :: が直前のテキスト側に残る
# [x] メタ情報: 引数名(位置+キーワード)・アリティ範囲・ブロック有無
# [x] メタ情報: 引数の無いオーバーロードは params=[]・arity=[0,0]
# [x] def self?. は # と . の両キーに登録される
# [x] alias メンバーは元メソッドのシグネチャを共有する
# [x] attr_reader/attr_writer は name / name= キーになり、型だけの
#     オーバーロード(メタ無し)になる
# [x] lookup: typechar i/s/m で引ける(m は # → . の順)
# [x] lookup: new は Class.new → Class#initialize の順でフォールバック
# [x] lookup: 別名リストの後ろの名前でもヒットする
# [x] lookup: 対応が無ければ nil(定数・特殊変数も nil)
# [x] apply: DB のエントリに rbs_sig(overloads 形式の JSON)が書き込まれる
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
        def meta: (Integer x, ?String y, *Integer rest, size: Integer, ?name: String) { (Integer) -> void } -> void
                | (Integer a, Integer b) ?{ () -> void } -> void
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
    overloads = @importer.signatures['Foo#bar']
    assert_equal 2, overloads.size
    assert_equal '(Integer base) -> String', join_text(overloads[0])
    assert_equal '(::Enumerator::Lazy) -> Array[Integer]', join_text(overloads[1])
  end

  def test_type_names_become_class_segments
    overloads = @importer.signatures['Foo#bar']
    assert_equal(
      [['t', '('], ['c', 'Integer'], ['t', ' base) -> '], ['c', 'String']],
      overloads[0]['segments'])
  end

  def test_namespace_prefix_stays_in_text_segment
    overloads = @importer.signatures['Foo#bar']
    assert_equal(
      [['t', '(::'], ['c', 'Enumerator::Lazy'], ['t', ') -> '],
       ['c', 'Array'], ['t', '['], ['c', 'Integer'], ['t', ']']],
      overloads[1]['segments'])
  end

  # 小文字のエイリアス型(hash 等)自体はテキストのままだが、その
  # ジェネリクス引数の中のクラス名はリンク化候補にする
  def test_alias_type_args_become_class_segments
    overloads = @importer.signatures['Foo#pairs']
    assert_equal(
      [['t', '(hash['], ['c', 'Symbol'], ['t', ', '], ['c', 'String'],
       ['t', ']) -> void']],
      overloads[0]['segments'])
  end

  # チャンク振り分け用のメタ情報。引数名は位置引数(rest 含む)+
  # キーワード名、アリティは位置引数の [最小, 最大](rest があれば nil)、
  # block は必須 "req" / 省略可能 "opt"(無ければキー自体無し)
  def test_overload_meta
    overloads = @importer.signatures['Foo#meta']
    assert_equal %w[x y rest size name], overloads[0]['params']
    assert_equal [1, nil], overloads[0]['arity']
    assert_equal 'req', overloads[0]['block']
    assert_equal %w[a b], overloads[1]['params']
    assert_equal [2, 2], overloads[1]['arity']
    assert_equal 'opt', overloads[1]['block']
  end

  def test_overload_meta_without_params
    overloads = @importer.signatures['Foo.build']
    assert_equal [], overloads[0]['params']
    assert_equal [0, 0], overloads[0]['arity']
    assert_nil overloads[0]['block']
    # 名前の無い位置引数はアリティにだけ数える
    assert_equal [], @importer.signatures['Foo#initialize'][0]['params']
    assert_equal [1, 1], @importer.signatures['Foo#initialize'][0]['arity']
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
    assert_equal({'segments' => [['c', 'String']]}, sigs['Foo#label'][0])
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
    assert_equal({'overloads' => @importer.signatures['Foo#bar']},
                 JSON.parse(bar.rbs_sig))
    assert_equal 1, stats[:entries_updated]
    assert_equal 1, stats[:sigs_matched]
    assert_equal 1, stats[:methods_missed]
  end

  def test_apply_leaves_unmatched_methods_untouched
    prefix = build_db('4.0')
    @importer.apply(BitClust::MethodDatabase.new(prefix))
    assert_nil find_entry(prefix, 'nope').rbs_signature_overloads
  end

  def test_apply_twice_is_idempotent
    prefix = build_db('4.0')
    @importer.apply(BitClust::MethodDatabase.new(prefix))
    stats = @importer.apply(BitClust::MethodDatabase.new(prefix))
    assert_equal 0, stats[:entries_updated]
    assert_equal 1, stats[:sigs_matched]
  end

  private

  def join_text(overload)
    overload['segments'].map {|_kind, text| text }.join
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

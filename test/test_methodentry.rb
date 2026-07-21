require 'test/unit'
require 'bitclust'
require 'bitclust/methoddatabase'
require 'tmpdir'
require 'fileutils'

class TestMethodEntryTitleLabels < Test::Unit::TestCase
  def test_title_labels_matches_label_when_no_alias
    lib, db = BitClust::RRDParser.parse(<<HERE, 'dummy')
= class Enumerable2
== Instance Methods
--- select -> Array

説明のためのエントリ
HERE
    _ = lib
    m = db.get_method(BitClust::MethodSpec.parse('Enumerable2#select'))
    assert_equal(['Enumerable2#select'], m.title_labels)
    assert_equal(m.label, m.title_labels.join(', '))
  end

  def test_title_labels_lists_every_alias
    lib, db = BitClust::RRDParser.parse(<<HERE, 'dummy')
= class Enumerable2
== Instance Methods
--- collect -> Array
--- map -> Array

説明のためのエントリ
HERE
    _ = lib
    m = db.get_method(BitClust::MethodSpec.parse('Enumerable2#collect'))
    assert_equal(['Enumerable2#collect', 'Enumerable2#map'], m.title_labels)
  end

  # #label omits the class prefix for special variables (e.g. "$;", not
  # "Kernel$;"); #title_labels must keep that convention for every alias,
  # unlike #labels which always includes the prefix.
  def test_title_labels_omits_class_prefix_for_special_variables
    lib, db = BitClust::RRDParser.parse(<<HERE, 'dummy')
= module Kernel
description
== Special Variables
--- $;
--- $FIELD_SEPARATOR

区切り文字。
HERE
    _ = lib
    m = db.get_method(BitClust::MethodSpec.parse('Kernel$;'))
    assert_equal('$;', m.label)
    assert_equal(['$;', '$FIELD_SEPARATOR'], m.title_labels)
    assert_equal(['Kernel$;', 'Kernel$FIELD_SEPARATOR'], m.labels)
  end

  def test_title_labels_matches_label_for_single_special_variable
    lib, db = BitClust::RRDParser.parse(<<HERE, 'dummy')
= module Kernel
description
== Special Variables
--- $stdout -> IO

標準出力。
HERE
    _ = lib
    m = db.get_method(BitClust::MethodSpec.parse('Kernel$stdout'))
    assert_equal(['$stdout'], m.title_labels)
    assert_equal(m.label, m.title_labels.join(', '))
  end
end

# メソッド名別の since/until (bitclust#132 P1)。
#
# テストリスト:
# [x] 新規エントリの since_map/until_map は空、since_of/until_of は nil
# [x] fill_since は初回のみ追加して true を返す。既に値があれば false で上書きしない
# [x] fill_until も同様
# [x] fill_since/fill_until は version に '=' や ',' を含むと ArgumentError
# [x] 実ディスク DB への保存→別インスタンスで再読込しても since_of/until_of が一致
# [x] 名前に '=' を含む（"==", "foo="）・',' を含む（"," ）・"-@" が
#     エンコード/デコードを経て正しく往復する
# [x] since_by_name/until_by_name のキー自体がプロパティファイルに無い
#     （旧DB）場合も落ちずに空配列として読める（Entry の '[String]' デシリアライザの
#     nil 安全化）
class TestMethodEntrySinceUntil < Test::Unit::TestCase
  def setup
    @dir = Dir.mktmpdir
    @db = BitClust::MethodDatabase.new(@dir)
    @db.init
    @db.transaction do
      @db.propset('version', '2.0')
      @db.propset('encoding', 'utf-8')
    end
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_defaults_are_empty
    m = build_entry('marker')
    assert_equal({}, m.since_map)
    assert_equal({}, m.until_map)
    assert_nil m.since_of('marker')
    assert_nil m.until_of('marker')
  end

  def test_fill_since_adds_once
    m = build_entry('marker')
    assert_equal(true, m.fill_since('marker', '2.0'))
    assert_equal('2.0', m.since_of('marker'))
    # 既に値があるので上書きされず false
    assert_equal(false, m.fill_since('marker', '3.0'))
    assert_equal('2.0', m.since_of('marker'))
  end

  def test_fill_until_adds_once
    m = build_entry('marker')
    assert_equal(true, m.fill_until('marker', '3.0'))
    assert_equal('3.0', m.until_of('marker'))
    assert_equal(false, m.fill_until('marker', '4.0'))
    assert_equal('3.0', m.until_of('marker'))
  end

  def test_fill_since_rejects_version_with_equal_or_comma
    m = build_entry('marker')
    assert_raise(ArgumentError) { m.fill_since('marker', '2.0=1') }
    assert_raise(ArgumentError) { m.fill_since('marker', '2.0,1') }
  end

  def test_fill_until_rejects_version_with_equal_or_comma
    m = build_entry('marker')
    assert_raise(ArgumentError) { m.fill_until('marker', '2.0=1') }
    assert_raise(ArgumentError) { m.fill_until('marker', '2.0,1') }
  end

  def test_roundtrip_through_disk
    m = build_entry('marker')
    m.fill_since('marker', '2.0')
    m.fill_until('marker', '3.0')
    m.save

    reloaded = reload_entry(m.id)
    assert_equal('2.0', reloaded.since_of('marker'))
    assert_equal('3.0', reloaded.until_of('marker'))
    assert_equal({'marker' => '2.0'}, reloaded.since_map)
    assert_equal({'marker' => '3.0'}, reloaded.until_map)
  end

  def test_roundtrip_names_with_special_characters
    [ '==', 'foo=', '-@', ',' ].each do |name|
      m = build_entry(name)
      m.fill_since(name, '2.0')
      m.save

      reloaded = reload_entry(m.id)
      assert_equal('2.0', reloaded.since_of(name),
                   "since_of(#{name.inspect}) should round-trip")
    end
  end

  def test_multiple_names_share_one_entry
    m = build_entry_with_names(['-@', 'dedup'])
    m.fill_since('-@', '2.0')
    m.fill_since('dedup', '3.0')
    m.save

    reloaded = reload_entry(m.id)
    assert_equal('2.0', reloaded.since_of('-@'))
    assert_equal('3.0', reloaded.since_of('dedup'))
    assert_equal({'-@' => '2.0', 'dedup' => '3.0'}, reloaded.since_map)
  end

  def test_missing_since_by_name_key_is_backward_compatible
    m = build_entry('old_method')
    m.save
    strip_property_line(m.id, 'since_by_name')
    strip_property_line(m.id, 'until_by_name')

    reloaded = reload_entry(m.id)
    assert_equal([], reloaded.since_by_name)
    assert_equal([], reloaded.until_by_name)
    assert_nil reloaded.since_of('old_method')
  end

  private

  def build_entry(name)
    build_entry_with_names([name])
  end

  def build_entry_with_names(names)
    id = BitClust::NameUtils.build_method_id('_builtin', 'Foo', :instance_method, names.first)
    m = BitClust::MethodEntry.new(@db, id)
    m.names = names
    m.visibility = :public
    m.kind = :defined
    m.source = "説明\n"
    m
  end

  def reload_entry(id)
    fresh_db = BitClust::MethodDatabase.new(@dir)
    BitClust::MethodEntry.new(fresh_db, id)
  end

  def property_file_path(id)
    File.join(@dir, BitClust::NameUtils.encodeid("method/#{id}"))
  end

  def strip_property_line(id, key)
    path = property_file_path(id)
    lines = File.readlines(path).reject {|l| l.start_with?("#{key}=") }
    File.write(path, lines.join)
  end
end

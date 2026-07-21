require 'bitclust/rrdparser'
require 'test/unit'

class TestRRDParser < Test::Unit::TestCase
  def test_title
    result = BitClust::RRDParser.split_doc <<HERE
= hoge
a
HERE
    assert_equal(["hoge", "a\n"], result)

    result = BitClust::RRDParser.split_doc <<HERE
==foo
a
=hoge
HERE
    assert_equal(["hoge", ""], result)


        result = BitClust::RRDParser.split_doc <<HERE
==[a:hoge]hoge
a
HERE
    assert_equal(["", "==[a:hoge]hoge\na\n"], result)
  end

  def test_undef
    result = BitClust::RRDParser.parse(<<HERE, 'dummy')
= module Dummy
== Instance Methods
--- test_undef
{: undef}

このメソッドは利用できない

HERE
    _library, methoddatabase = result
    test_undef_spec = BitClust::MethodSpec.parse('Dummy#test_undef')
    assert_equal(:undefined, methoddatabase.get_method(test_undef_spec).kind)
  end

  def test_nomethod
    result = BitClust::RRDParser.parse(<<HERE, 'dummy')
= module Dummy
== Instance Methods
--- test_nomethod
{: nomethod}

説明のためここに記載しているメソッド

HERE
    _library, methoddatabase = result
    test_nomethod_spec = BitClust::MethodSpec.parse('Dummy#test_nomethod')
    assert_equal(:nomethod, methoddatabase.get_method(test_nomethod_spec).kind)
  end

  def test_unknown_method_attribute
    assert_raise(BitClust::ParseError) do
      BitClust::RRDParser.parse(<<HERE, 'dummy')
= module Dummy
== Instance Methods
--- test_typo
{: nomthod}

typo したフラグはエラーになる

HERE
    end
  end

  def test_since_attribute_sets_since_of_name
    _library, db = BitClust::RRDParser.parse(<<HERE, 'dummy')
= module Dummy
== Instance Methods
--- test_since
{: since="2.5"}

説明

HERE
    entry = db.get_method(BitClust::MethodSpec.parse('Dummy#test_since'))
    assert_equal('2.5', entry.since_of('test_since'))
    assert_nil(entry.until_of('test_since'))
  end

  def test_until_attribute_sets_until_of_name
    _library, db = BitClust::RRDParser.parse(<<HERE, 'dummy')
= module Dummy
== Instance Methods
--- test_until
{: until="3.0"}

説明

HERE
    entry = db.get_method(BitClust::MethodSpec.parse('Dummy#test_until'))
    assert_equal('3.0', entry.until_of('test_until'))
    assert_nil(entry.since_of('test_until'))
  end

  def test_malformed_since_attribute_is_rejected
    ['since=2.5', 'since=""', 'since="3,2"', 'since="abc"', 'foo="1"'].each do |token|
      assert_raise(BitClust::ParseError, token) do
        BitClust::RRDParser.parse(<<HERE, 'dummy')
= module Dummy
== Instance Methods
--- test_since
{: #{token}}

説明

HERE
      end
    end
  end

  def test_duplicate_since_attribute_on_one_signature_is_rejected
    assert_raise(BitClust::ParseError) do
      BitClust::RRDParser.parse(<<HERE, 'dummy')
= module Dummy
== Instance Methods
--- test_since
{: since="1.0" since="2.0"}

説明

HERE
    end
  end

  def test_instance_methods
    result = BitClust::RRDParser.parse(<<HERE, 'dummy')
= module Dummy

== Instance Methods
--- im

== Private Methods

--- pvi

== Protected Instance Methods

--- pti

HERE
    _library, methoddatabase = result

    test_undef_spec = BitClust::MethodSpec.parse('Dummy#im')
    assert_equal(true, methoddatabase.get_method(test_undef_spec).public?)

    test_undef_spec = BitClust::MethodSpec.parse('Dummy#pvi')
    assert_equal(true, methoddatabase.get_method(test_undef_spec).private?)

    test_undef_spec = BitClust::MethodSpec.parse('Dummy#pti')
    assert_equal(true, methoddatabase.get_method(test_undef_spec).protected?)
  end
end

class TestRRDParserMethodAttributeBinding < Test::Unit::TestCase
  # {: ...} は直前のシグネチャ行のみに束縛される(kramdown の Block IAL と同じ)。
  # kind はエントリ単位なので、別名エントリでは全シグネチャに同じ属性が必要
  def test_attribute_on_every_alias_signature
    result = BitClust::RRDParser.parse(<<HERE, 'dummy')
= module Dummy
== Instance Methods
--- test_foo
{: nomethod}
--- test_bar
{: nomethod}

説明のためのエントリ

HERE
    _library, db = result
    foo = db.get_method(BitClust::MethodSpec.parse('Dummy#test_foo'))
    assert_equal(:nomethod, foo.kind)
    assert_equal(['test_bar', 'test_foo'], foo.names)
  end

  def test_attribute_missing_on_some_alias_signature_is_rejected
    assert_raise(BitClust::ParseError) do
      BitClust::RRDParser.parse(<<HERE, 'dummy')
= module Dummy
== Instance Methods
--- test_foo
{: nomethod}
--- test_bar

説明のためのエントリ

HERE
    end
  end

  def test_since_attribute_differs_per_alias_signature
    # since=/until= はシグネチャ単位で束縛され、nomethod/undef と違って
    # エイリアスごとに異なる値を持てる(全シグネチャ一致は要求しない)
    result = BitClust::RRDParser.parse(<<HERE, 'dummy')
= module Dummy
== Instance Methods
--- test_foo
{: since="2.0.0"}
--- test_bar
{: since="3.0"}

説明のためのエントリ

HERE
    _library, db = result
    entry = db.get_method(BitClust::MethodSpec.parse('Dummy#test_foo'))
    assert_equal(['test_bar', 'test_foo'], entry.names)
    assert_equal('2.0.0', entry.since_of('test_foo'))
    assert_equal('3.0', entry.since_of('test_bar'))
  end

  def test_since_attribute_on_only_one_alias_signature_is_allowed
    result = BitClust::RRDParser.parse(<<HERE, 'dummy')
= module Dummy
== Instance Methods
--- test_foo
{: since="2.0.0"}
--- test_bar

説明のためのエントリ

HERE
    _library, db = result
    entry = db.get_method(BitClust::MethodSpec.parse('Dummy#test_foo'))
    assert_equal('2.0.0', entry.since_of('test_foo'))
    assert_nil(entry.since_of('test_bar'))
  end

  def test_undef_and_since_mixed_on_same_signature_line
    result = BitClust::RRDParser.parse(<<HERE, 'dummy')
= module Dummy
== Instance Methods
--- test_foo
{: undef since="3.0"}

説明のためのエントリ

HERE
    _library, db = result
    entry = db.get_method(BitClust::MethodSpec.parse('Dummy#test_foo'))
    assert_equal(:undefined, entry.kind)
    assert_equal('3.0', entry.since_of('test_foo'))
  end

  def test_bare_attribute_uniformity_still_enforced_when_since_present
    # since= はシグネチャ単位で例外的に一致要求から外れるが、
    # undef/nomethod のエントリ単位の一致要求はそのまま生きている
    assert_raise(BitClust::ParseError) do
      BitClust::RRDParser.parse(<<HERE, 'dummy')
= module Dummy
== Instance Methods
--- test_foo
{: undef since="3.0"}
--- test_bar
{: since="3.0"}

説明のためのエントリ

HERE
    end
  end

  def test_detached_attribute_line_is_not_a_method_attribute
    # 空行を挟んだ {: ...} はシグネチャに束縛されない(ただの本文)
    result = BitClust::RRDParser.parse(<<HERE, 'dummy')
= module Dummy
== Instance Methods
--- test_foo

{: nomethod}

説明

HERE
    _library, db = result
    assert_equal(:defined, db.get_method(BitClust::MethodSpec.parse('Dummy#test_foo')).kind)
  end
end

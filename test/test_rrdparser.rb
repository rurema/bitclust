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

  def test_reserved_method_attribute_is_rejected
    # since/until は #132 で対応予定。未対応のうちはエラーにして気づけるようにする
    assert_raise(BitClust::ParseError) do
      BitClust::RRDParser.parse(<<HERE, 'dummy')
= module Dummy
== Instance Methods
--- test_since
{: since="1.9.1"}

まだサポートされない

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

class TestRRDParserLegacyUndef < Test::Unit::TestCase
  # 旧 @undef の後方互換。doctree master が {: undef} へ移行するまでの
  # 過渡期用で、移行完了後に削除する
  def test_legacy_undef_paragraph_still_sets_kind
    result = BitClust::RRDParser.parse(<<HERE, 'dummy')
= module Dummy
== Instance Methods
--- test_undef

@undef

HERE
    _library, db = result
    assert_equal(:undefined, db.get_method(BitClust::MethodSpec.parse('Dummy#test_undef')).kind)
  end
end

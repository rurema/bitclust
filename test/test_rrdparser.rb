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

@undef

このメソッドは利用できない

HERE
    _library, methoddatabase = result
    test_undef_spec = BitClust::MethodSpec.parse('Dummy#test_undef')
    assert_equal(:undefined, methoddatabase.get_method(test_undef_spec).kind)
  end

  def test_protected_instance_method
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

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
end

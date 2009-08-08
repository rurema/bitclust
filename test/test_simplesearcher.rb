require 'test/unit'
require 'bitclust'
require 'bitclust/simplesearcher'
require 'optparse'


class TestSearcher <  Test::Unit::TestCase

  def setup
    s = <<HERE
= class Hoge
== Class Methods
--- hoge
= class Hoge::Bar
== Class Methods
--- bar
= reopen Kernel
== Special Variables
--- $spespe

--- $/

--- $$
HERE
    _, @db = BitClust::RRDParser.parse(s, 'hoge')
  end

  include BitClust::SimpleSearcher
  def test_simple_search
    [['Ho',     'Hoge'],
     ['Hoge.h', 'hoge'],
     ['$sp',    'spespe'],
     ['$/',     '/'],
     ['$$',     '$'],
     ['B.b',    'bar'],
     ['Hoge::B','Hoge::Bar'],
     ['B b',    'bar'],
     [' B b c ','bar'],
     ['b B',    'bar'],
    ].each{|q, expected|
      ret = search_pattern(@db, q)
      assert_not_equal([], ret, q)
      assert_equal(expected, ret[0].name, q)
    }
    assert_equal([], search_pattern(@db, " "), 'space')
    assert_equal([], search_pattern(@db, ""), 'blank')
  end
end

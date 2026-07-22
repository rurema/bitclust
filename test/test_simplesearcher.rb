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
== Module Functions
--- open

== Instance Methods
--- puts

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

  # bitclust#250 follow-up: the dynamic server's /search accepts free-text
  # queries, and a module function may be typed in either notation --
  # "Kernel.#open" (bitclust's own internal spec-string form, still what
  # docs for Ruby < 4.0 display) or "Kernel?.open" (what docs for Ruby >=
  # 4.0 display since #277). Both must resolve to the same method,
  # regardless of which notation the *query* uses -- the query parser has
  # no idea (and shouldn't need to know) which doc version the user is
  # thinking of.
  def test_module_function_query_notation
    [['Kernel?.open', 'open'],  # new (>=4.0 display) notation
     ['Kernel.#open', 'open'],  # existing (bitclust-internal) notation: regression check
     ['?.open',       'open'],  # bare module-function marker, no class name
     ['Kernel#puts',  'puts'],  # instance method: unaffected by the "?." change
    ].each{|q, expected|
      ret = search_pattern(@db, q)
      assert_not_equal([], ret, q)
      assert_equal(expected, ret[0].name, q)
    }
    # Singleton-method dot notation ('Hoge.h' => 'hoge' in test_simple_search
    # above) is also unaffected; kept there rather than duplicated here.
  end
end

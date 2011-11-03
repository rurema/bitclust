require 'test/unit'
require 'bitclust/database'
require 'bitclust/refsdatabase'
require 'bitclust/rrdparser'
require 'stringio'

class Test_RefsDatabase < Test::Unit::TestCase

  S1 = <<HERE
===[a:a3] A3
====[a:a4] A4
=====[a:a5] A5
======[a:a6] A6

= class Hoge
===[a:b3] B3
a a a a

===[a:c3] C3
====[a:c4] C4
=====[a:c5] C5
======[a:c6] C6

== Class Methods
--- hoge
= class Hoge::Bar
== Class Methods
--- bar
===[a:d3] D3
====[a:d4] D4
=====[a:d5] D5
======[a:d6] D6
= reopen Kernel
== Special Variables
--- $spespe
===[a:e3] E3
====[a:e4] E4
=====[a:e5] E5
======[a:e6] E6
HERE

  S2 = <<HERE
class,klass,linkid,description
method,method,linkid,description
method,method,linkid2,des\\,cription
HERE
  
  def test_refs
    refs = BitClust::RefsDatabase.load(StringIO.new(S2))
    assert refs["class", "klass", "linkid"]
    refs["class", "klass", "linkid3"] = "hoge"
    assert_equal( "hoge", refs["class", "klass", "linkid3"] )
    sio = StringIO.new
    assert_nothing_raised do
      refs.save(sio)
    end
    assert_match(/des\\,cription/, sio.string)
  end

  def test_make_refs
    _, db = BitClust::RRDParser.parse(S1, 'dummy')
    db.make_refs
    ['a3', 'a4', 'a5', 'a6'].each do |s|
      assert_equal(s.upcase, db.refs['library', 'dummy', s])
    end
    ['c3', 'c4', 'c5', 'c6'].each do |s|
      assert_equal(s.upcase, db.refs['class',   'Hoge',  s])
    end
    ['d3', 'd4', 'd5', 'd6'].each do |s|
      assert_equal(s.upcase, db.refs['method',  'Hoge::Bar.bar', s])
    end
    ['e3', 'e4', 'e5', 'e6'].each do |s|
      assert_equal(s.upcase, db.refs['method',  'Kernel$spespe', s])
    end
  end
end

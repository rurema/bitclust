require 'test/unit'
require 'bitclust/database'
require 'bitclust/refsdatabase'
require 'stringio'

class Test_RefsDatabase < Test::Unit::TestCase

  S1 = <<HERE
===[a:000] 000

= class Hoge
===[a:aaa] AAA
a a a a

===[a:bbb] BBB

== Class Methods
--- hoge
= class Hoge::Bar
== Class Methods
--- bar
===[a:ddd] DDD
= reopen Kernel
== Special Variables
--- $spespe
===[a:ccc] CCC
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
    assert_equal('000', db.refs['library', 'dummy', '000'])
    assert_equal('AAA', db.refs['class',   'Hoge',  'aaa'])
    assert_equal('CCC', db.refs['method',  'Kernel$spespe', 'ccc'])
  end
end

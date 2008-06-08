require 'test/unit'
require 'bitclust/refsdatabase'
require 'stringio'

class Test_RefsDatabase < Test::Unit::TestCase

  def setup
    @s = <<HERE
class,klass,linkid,description
method,method,linkid,description
method,method,linkid2,des\\,cription
HERE
    @refs = BitClust::RefsDatabase.load(StringIO.new(@s))
  end

  def test_refs
    assert @refs["class", "klass", "linkid"]
    @refs["class", "klass", "linkid3"] = "hoge"
    assert_equal( "hoge", @refs["class", "klass", "linkid3"] )
    sio = StringIO.new
    assert_nothing_raised do
      @refs.save(sio)
    end
    assert_match(/des\\,cription/, sio.string)
  end
end

require 'test/unit'
require 'bitclust/refsdatabase'
require 'stringio'

class Test_RefsDatabase < Test::Unit::TestCase

  def setup
    @s = <<HERE
class,klass,linkid,description
method,method,linkid,description
HERE
    @refs = BitClust::RefsDatabase.load(@s)
  end

  def test_refs
    assert @refs["class", "klass", "linkid"]
    sio = StringIO.new
    @refs.save(sio)
    assert_equal(@s, sio.string)
  end
end

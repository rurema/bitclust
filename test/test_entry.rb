require 'bitclust'
require 'test/unit'

class TestClassEntry < Test::Unit::TestCase
  def setup
    s = <<HERE
= class Hoge
== Class Methods
--- hoge
= class Bar < Hoge
== Class Methods
--- bar
HERE
    @lib, = BitClust::RRDParser.parse(s, 'hoge')
  end

  def test_entries
    assert_equal(['bar', 'hoge'],
                 @lib.fetch_class("Bar").entries(1).map{|e| e.name}.sort)
  end
end


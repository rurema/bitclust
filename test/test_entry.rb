require 'bitclust'
require 'test/unit'
require 'stringio'

module BitClust
  class RRDParser    
    def RRDParser.parse(io, lib, params = {"version" => "1.9.0"})
      parser = new(Database.dummy(params))
      parser.parse(io, lib, params)
    end
  end
end

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
    @lib = BitClust::RRDParser.parse(StringIO.new(s), 'hoge')
  end

  def test_entries
    assert_equal(['bar', 'hoge'],
                 @lib.fetch_class("Bar").entries(1).map{|e| e.name}.sort)
  end
end


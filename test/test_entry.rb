require 'bitclust'
require 'test/unit'

class TestClassEntry < Test::Unit::TestCase
  def setup
    s = <<HERE
= class Hoge
alias HogeHoge
alias HogeHogeHoge
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

  def test_aliases
    assert_equal(['HogeHoge', 'HogeHogeHoge'],
                 @lib.fetch_class("Hoge").aliases.map{|e| e.name}.sort)
  end

  def test_aliasof
    assert_equal(nil, @lib.fetch_class("Hoge").aliasof)
    assert_equal("Hoge", @lib.fetch_class("HogeHoge").aliasof.name)
  end

  def test_realname
    assert_equal('Hoge', @lib.fetch_class("Hoge").realname)
    assert_equal('Hoge', @lib.fetch_class("HogeHoge").realname)
  end
end


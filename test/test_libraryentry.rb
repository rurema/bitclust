require 'bitclust'
require 'test/unit'
require 'bitclust/libraryentry'

class TestLibraryEntry < Test::Unit::TestCase
  include BitClust

  def setup
    s = <<DOC
require hoge/bar
require hoge/baz
require hoge/bar

= class Hoge
== Class Methods
--- hoge
= class Bar < Hoge
== Class Methods
--- bar
DOC
    @lib_entry, @db = BitClust::RRDParser.parse(s, 'hoge')
    @sublibrary = LibraryEntry.new(@db, 'testsub')
  end

  def test_sublibrary
    @lib_entry.sublibrary(@sublibrary)
    assert_equal(['testsub'], @lib_entry.sublibraries.map(&:name))
    @lib_entry.sublibrary(@sublibrary)
    assert_equal(['testsub'], @lib_entry.sublibraries.map(&:name))
  end
end

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
= class Err < Exception
= class Err2 < Err
alias Err2Alias
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

  def test_error_classes
    assert_equal(["Err", "Err2", "Err2Alias"],
                 @lib_entry.error_classes.map(&:name).sort)
  end
end

require "test/unit"
require "bitclust"
require "bitclust/searcher"

class TestTerminalView < Test::Unit::TestCase
  include BitClust

  def test_show_class
    view = TerminalView.new(Plain.new, {})
    db = Database.dummy
    foo = ClassEntry.new(db, "Foo")
    bar = ClassEntry.new(db, "Bar")
    out, err = capture_output do
      assert_nothing_raised do
        view.show_class([foo, bar])
      end
    end
    assert_equal %w[Bar Foo], out.split
    assert_empty err
  end
end

require 'test/unit'
require 'bitclust'
require 'bitclust/subcommands/statichtml_command'

class TestStatichtmlURLMapperEx < Test::Unit::TestCase
  def setup
    @urlmapper = BitClust::Subcommands::StatichtmlCommand::URLMapperEx.new(
      :suffix => 'html',
      :edit_base_url => 'https://github.com/rurema/doctree/edit/master',
    )
  end

  # The edit URL must not contain a line number, so that shifting source lines
  # does not churn the generated HTML diff.
  def test_edit_url_has_no_line_number
    location = BitClust::Location.new('refm/api/src/_builtin/Array', 42)
    assert_equal('https://github.com/rurema/doctree/edit/master/refm/api/src/_builtin/Array',
                 @urlmapper.edit_url(location))
  end

  # A location restored from the database has no line number (nil); the edit URL
  # must still be a clean file link without a trailing "#L".
  def test_edit_url_without_line_in_location
    location = BitClust::Location.new('refm/api/src/_builtin/Array', nil)
    assert_equal('https://github.com/rurema/doctree/edit/master/refm/api/src/_builtin/Array',
                 @urlmapper.edit_url(location))
  end
end

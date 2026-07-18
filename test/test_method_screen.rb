require 'test/unit'
require 'bitclust'
require 'bitclust/screen'

# Covers data/bitclust/template.offline, used by `bitclust statichtml` (the
# production docs.ruby-lang.org build) and `bitclust chm`.
#
# NOTE: only one templatedir is exercised here on purpose. Screen#run_template
# caches the compiled ERB template methods on the *class* (MethodScreen),
# keyed only by method name (e.g. "method_template"), regardless of which
# @template_repository the instance was built with. So constructing
# MethodScreen from two different templatedirs (e.g. this one and
# data/bitclust/template) within the same process is unreliable: whichever
# templatedir's ERB gets compiled first "wins" for every MethodScreen built
# afterwards, in every test file, for the rest of the run. This is a
# pre-existing quirk of Screen, not something introduced here.
#
# data/bitclust/template, data/bitclust/template.lillia and
# data/bitclust/template.epub were hand-verified (each in its own process,
# not committed as an automated test here) to build @title the same way as
# template.offline below, just keeping their pre-existing
# "#{entry.type_label} #{entry.label}" prefix -- i.e. the fix is
# entry.label -> entry.title_labels.join(', ') in all four `method`
# templates, so the CHM (template) and EPUB (template.epub) screens get the
# same alias listing.
class TestMethodScreenTitle < Test::Unit::TestCase
  SRC = <<'HERE'
= class Enumerable2 < Object
enumerable class
== Instance Methods
--- collect -> Array
--- map -> Array

説明のためのエントリ

--- select -> Array

説明2
HERE

  def setup
    @lib, @db = BitClust::RRDParser.parse(SRC, 'testlib')
    datadir = File.expand_path('../data/bitclust', __dir__)
    @manager = BitClust::ScreenManager.new(
      :templatedir => "#{datadir}/template.offline",
      :catalogdir => "#{datadir}/catalog",
      :encoding => 'utf-8',
      :default_encoding => 'utf-8',
      :base_url => '',
      :target_version => '3.4'
    )
  end

  def method_html(spec)
    entry = @db.get_method(BitClust::MethodSpec.parse(spec))
    @manager.method_screen([entry], :database => @db).body
  end

  def title_of(html)
    html[/<title>(.*?) \(Ruby/, 1]
  end

  # template.offline's <title> has never included the "instance method"
  # type_label prefix (only entry.label); the alias fix must keep that
  # pre-existing convention and just expand the single name to every alias.
  def test_title_lists_every_alias
    assert_equal('Enumerable2#collect, Enumerable2#map',
                 title_of(method_html('Enumerable2#collect')))
  end

  # Both aliases are the very same entry, so they share one page/title
  # regardless of which alias URL was requested.
  def test_title_is_the_same_regardless_of_which_alias_was_requested
    assert_equal(method_html('Enumerable2#collect'), method_html('Enumerable2#map'))
  end

  # A method without any alias renders exactly as before: only its own name.
  def test_title_is_unchanged_for_a_method_without_aliases
    html = method_html('Enumerable2#select')
    assert_equal('Enumerable2#select', title_of(html))
  end

  # Only the <title> tag changes; the on-page h1 headline keeps showing only
  # the entry's own (alphabetically-first) name, as before.
  def test_h1_headline_is_not_affected
    html = method_html('Enumerable2#collect')
    assert_match(%r{<h1>instance method Enumerable2\#collect</h1>}, html)
    assert_not_match(/<h1>[^<]*Enumerable2#map/, html)
  end
end

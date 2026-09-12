require 'test/unit'
require 'bitclust'
require 'bitclust/subcommands/chm_command'

# bitclust chm の索引(.hhc/.hhk)生成(rurema/bitclust の出力監査 2026-09):
# Sitemap::Content#to_html が文字列リテラルに << していたため、
# frozen_string_literal の導入以降 FrozenError で落ちていた
class TestChmSitemap < Test::Unit::TestCase
  def test_to_html_builds_nested_sitemap
    root = BitClust::Subcommands::ChmCommand::Sitemap.new('Ruby', 'doc/index.html')
    child = BitClust::Subcommands::ChmCommand::Sitemap::Content.new('Array <=> & "q"', 'class/-array.html')
    root << child
    html = root.to_html
    assert_match(%r{<param name="Name" value="Ruby">}, html)
    assert_match(%r{<param name="Local" value="doc/index.html">}, html)
    assert_match(%r{<UL>.*Array &lt;=&gt; &amp; &quot;q&quot;.*</UL>}m, html)
  end

  def test_to_html_without_children_has_no_ul
    leaf = BitClust::Subcommands::ChmCommand::Sitemap::Content.new('Leaf')
    html = leaf.to_html
    assert_not_match(/<UL>/, html)
    assert_not_match(/Local/, html)
  end
end

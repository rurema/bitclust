require 'test/unit'
require 'uri'
require 'bitclust'
require 'bitclust/screen'

class TestOpenSearchDescriptionScreen < Test::Unit::TestCase
  SRC = <<'HERE'
= class Foo
description
HERE

  def screen
    _lib, db = BitClust::RRDParser.parse(SRC, 'testlib', {'version' => '3.4'})
    datadir = File.expand_path('../data/bitclust', __dir__)
    manager = BitClust::ScreenManager.new(
      :templatedir => "#{datadir}/template",
      :catalogdir => "#{datadir}/catalog",
      :encoding => 'utf-8',
      :default_encoding => 'utf-8',
      :base_url => '',
      :cgi_url => '/view',
      :target_version => '3.4'
    )
    manager.opensearchdescription_screen(URI.parse('http://example.com/view/opensearchdescription'),
                                         :database => db)
  end

  def test_body_is_bare_xml_without_html_layout
    body = screen.body
    assert_match(/\A<\?xml/, body)
    assert_not_include(body, '<html')
    assert_match(%r{\A<\?xml[^>]*\?>\s*<OpenSearchDescription\b.*</OpenSearchDescription>\s*\z}m, body)
    assert_include(body, 'http://example.com/view/search')
  end

  def test_content_type_is_opensearch_xml
    assert_equal 'application/opensearchdescription+xml; charset=utf-8', screen.content_type
  end
end

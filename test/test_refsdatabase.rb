require 'test/unit'
require 'bitclust/database'
require 'bitclust/refsdatabase'
require 'bitclust/rrdparser'
require 'stringio'

class Test_RefsDatabase < Test::Unit::TestCase

  S1 = <<HERE
===[a:a3] A3
====[a:a4] A4
=====[a:a5] A5
======[a:a6] A6

= class Hoge
===[a:b3] B3
a a a a

===[a:c3] C3
====[a:c4] C4
=====[a:c5] C5
======[a:c6] C6

== Class Methods
--- hoge
= class Hoge::Bar
== Class Methods
--- bar
===[a:d3] D3
====[a:d4] D4
=====[a:d5] D5
======[a:d6] D6
= reopen Kernel
== Special Variables
--- $spespe
===[a:e3] E3
====[a:e4] E4
=====[a:e5] E5
======[a:e6] E6
= object ARGF
===[a:f3] F3
====[a:f4] F4
=====[a:f5] F5
======[a:f6] F6
HERE

  S2 = <<HERE
class,klass,linkid,description
method,method,linkid,description
method,method,linkid2,des\\,cription
HERE
  
  def test_refs
    refs = BitClust::RefsDatabase.load(StringIO.new(S2))
    assert refs["class", "klass", "linkid"]
    refs["class", "klass", "linkid3"] = "hoge"
    assert_equal( "hoge", refs["class", "klass", "linkid3"] )
    sio = StringIO.new
    assert_nothing_raised do
      refs.save(sio)
    end
    assert_match(/des\\,cription/, sio.string)
  end

  def test_make_refs
    _, db = BitClust::RRDParser.parse(S1, 'dummy')
    db.make_refs
    ['a3', 'a4', 'a5', 'a6'].each do |s|
      assert_equal(s.upcase, db.refs['library', 'dummy', s])
    end
    ['c3', 'c4', 'c5', 'c6'].each do |s|
      assert_equal(s.upcase, db.refs['class',   'Hoge',  s])
    end
    ['d3', 'd4', 'd5', 'd6'].each do |s|
      assert_equal(s.upcase, db.refs['method',  'Hoge::Bar.bar', s])
    end
    ['e3', 'e4', 'e5', 'e6'].each do |s|
      assert_equal(s.upcase, db.refs['method',  'Kernel$spespe', s])
    end
    ['f3', 'f4', 'f5', 'f6'].each do |s|
      assert_equal(s.upcase, db.refs['class',  'ARGF', s])
    end
  end

  # rd 形式の [a:xxx] アンカーもハイフンを含められる（doctree/bitclust#(このPR)）
  S3 = <<HERE
===[a:with-hyphen] With Hyphen
HERE

  def test_make_refs_rd_anchor_with_hyphen
    _, db = BitClust::RRDParser.parse(S3, 'dummy')
    db.make_refs
    assert_equal('With Hyphen', db.refs['library', 'dummy', 'with-hyphen'])
  end

  # md ソースの見出しアンカー {#xxx} 収集はハイフンを許容する
  # （doctree/manual の glossary.md 等、用語アンカーはハイフン区切り）
  def test_extract_markdown_heading_anchor_with_hyphen
    db = BitClust::MethodDatabase.dummy("version" => "3.4.0")
    entry = BitClust::DocEntry.new(db, 'glossary')
    entry.source = "### スレッドセーフ {#thread-safe}\n\n本文。\n"
    refs = BitClust::RefsDatabase.new
    refs.extract(entry)
    assert_equal('スレッドセーフ', refs['doc', 'glossary', 'thread-safe'])
  end

  # 従来のアンダースコア・単語アンカーの回帰が無いことも確認する
  def test_extract_markdown_heading_anchor_with_underscore
    db = BitClust::MethodDatabase.dummy("version" => "3.4.0")
    entry = BitClust::DocEntry.new(db, 'glossary')
    entry.source = "### 見出し {#my_anchor}\n\n本文。\n"
    refs = BitClust::RefsDatabase.new
    refs.extract(entry)
    assert_equal('見出し', refs['doc', 'glossary', 'my_anchor'])
  end
end

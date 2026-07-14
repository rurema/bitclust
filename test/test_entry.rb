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
hoge
--- fuga
{: undef}
fuga
== Instance Methods
--- fugafuga
{: undef}
fugafuga
= class Bar < Hoge
== Class Methods
--- bar
= class Err < Exception
alias ErrErr
HERE
    @lib, = BitClust::RRDParser.parse(s, 'hoge')
  end

  def test_entries
    assert_equal(['bar', 'fuga', 'fugafuga', 'hoge'],
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

  def test_error_class?
    assert(!@lib.fetch_class("Hoge").error_class?)
    assert(@lib.fetch_class("Err").error_class?)
    assert(!@lib.fetch_class("HogeHoge").error_class?)
    assert(@lib.fetch_class("ErrErr").error_class?)
  end

  def test_partitioned_entries
    parts = @lib.fetch_class('Hoge').partitioned_entries
    assert_equal(['fuga', 'fugafuga'], parts.undefined.map(&:name))
  end

  def test_superclass
    assert('Exception', @lib.fetch_class("Err").superclass.name)
    assert('Exception', @lib.fetch_class("ErrErr").superclass.name)
  end

  def test_instance_method?
    bar = @lib.fetch_class("Bar")
    assert(bar.instance_method?('fugafuga'))
    assert(!bar.instance_method?('fugafuga', false))
    hoge = @lib.fetch_class("Hoge")
    assert(hoge.instance_method?('fugafuga'))
    assert(hoge.instance_method?('fugafuga', false))
  end
end

class TestEntryDescription < Test::Unit::TestCase
  def parse_class(class_source)
    lib, = BitClust::RRDParser.parse(class_source, 'hoge')
    lib.fetch_class('Hoge')
  end

  def test_description_truncates_newline_between_non_ascii
    klass = parse_class(<<HERE)
= class Hoge
これは1行目で
あとに続きます。

以降の段落は含まれません。
HERE
    assert_equal('これは1行目であとに続きます。', klass.description)
  end

  def test_description_truncates_consecutive_newlines_between_non_ascii
    klass = parse_class(<<HERE)
= class Hoge
あい
うえ
おか。
HERE
    assert_equal('あいうえおか。', klass.description)
  end

  def test_description_converts_newline_to_space_around_ascii
    klass = parse_class(<<HERE)
= class Hoge
first line
second line
HERE
    assert_equal('first line second line', klass.description)
  end

  def test_description_replaces_bracket_link_with_plain_text
    klass = parse_class(<<HERE)
= class Hoge
自身の hostname を文字列で返します。また、[[m:URI::Generic#host]] が設
定されていない場合は [[c:Array]] を返します。
HERE
    assert_equal('自身の hostname を文字列で返します。また、URI::Generic#host が設定されていない場合は Array を返します。',
                 klass.description)
  end

  def test_description_replaces_indexer_bracket_link
    klass = parse_class(<<HERE)
= class Hoge
[[m:String#[] ]] を参照。
HERE
    assert_equal('String#[] を参照。', klass.description)
  end

  def test_method_description_is_plain_text
    klass = parse_class(<<HERE)
= class Hoge
== Instance Methods
--- fuga

[[c:Array]] を日本語で
返します。

次の段落。
HERE
    method = klass.entries.detect {|m| m.name == 'fuga' }
    assert_equal('Array を日本語で返します。', method.description)
  end
end

class TestEntryNomethod < Test::Unit::TestCase
  def parse_class(class_source)
    lib, = BitClust::RRDParser.parse(class_source, 'hoge')
    lib.fetch_class('Hoge')
  end

  def test_nomethod_is_partitioned_separately
    klass = parse_class(<<HERE)
= class Hoge
== Instance Methods
--- fuga
{: nomethod}

説明のためのエントリです。
HERE
    parts = klass.partitioned_entries
    assert_equal(['fuga'], parts.nomethod.map(&:name))
    assert_equal([], parts.instance_methods.map(&:name))
  end

  def test_redefined_is_partitioned_separately
    klass = parse_class(<<HERE)
= class Hoge
== Instance Methods
--- bar

説明です。

= redefine Hoge
== Instance Methods
--- baz

再定義の説明です。
HERE
    parts = klass.partitioned_entries
    assert_equal(['baz'], parts.redefined.map(&:name))
    assert_equal(['bar'], parts.instance_methods.map(&:name))
  end

  def test_description_skips_leading_metadata_paragraph
    klass = parse_class(<<HERE)
= class Hoge
== Instance Methods
--- fuga
{: nomethod}

説明のためのエントリです。
HERE
    method = klass.entries.detect {|m| m.name == 'fuga' }
    assert_equal('説明のためのエントリです。', method.description)
  end

  def test_description_is_empty_when_only_metadata
    klass = parse_class(<<HERE)
= class Hoge
== Instance Methods
--- fuga
{: undef}
HERE
    method = klass.entries.detect {|m| m.name == 'fuga' }
    assert_equal('', method.description)
  end
end

require 'test/unit'
require 'bitclust'

class TestMethodEntryTitleLabels < Test::Unit::TestCase
  def test_title_labels_matches_label_when_no_alias
    lib, db = BitClust::RRDParser.parse(<<HERE, 'dummy')
= class Enumerable2
== Instance Methods
--- select -> Array

説明のためのエントリ
HERE
    _ = lib
    m = db.get_method(BitClust::MethodSpec.parse('Enumerable2#select'))
    assert_equal(['Enumerable2#select'], m.title_labels)
    assert_equal(m.label, m.title_labels.join(', '))
  end

  def test_title_labels_lists_every_alias
    lib, db = BitClust::RRDParser.parse(<<HERE, 'dummy')
= class Enumerable2
== Instance Methods
--- collect -> Array
--- map -> Array

説明のためのエントリ
HERE
    _ = lib
    m = db.get_method(BitClust::MethodSpec.parse('Enumerable2#collect'))
    assert_equal(['Enumerable2#collect', 'Enumerable2#map'], m.title_labels)
  end

  # #label omits the class prefix for special variables (e.g. "$;", not
  # "Kernel$;"); #title_labels must keep that convention for every alias,
  # unlike #labels which always includes the prefix.
  def test_title_labels_omits_class_prefix_for_special_variables
    lib, db = BitClust::RRDParser.parse(<<HERE, 'dummy')
= module Kernel
description
== Special Variables
--- $;
--- $FIELD_SEPARATOR

区切り文字。
HERE
    _ = lib
    m = db.get_method(BitClust::MethodSpec.parse('Kernel$;'))
    assert_equal('$;', m.label)
    assert_equal(['$;', '$FIELD_SEPARATOR'], m.title_labels)
    assert_equal(['Kernel$;', 'Kernel$FIELD_SEPARATOR'], m.labels)
  end

  def test_title_labels_matches_label_for_single_special_variable
    lib, db = BitClust::RRDParser.parse(<<HERE, 'dummy')
= module Kernel
description
== Special Variables
--- $stdout -> IO

標準出力。
HERE
    _ = lib
    m = db.get_method(BitClust::MethodSpec.parse('Kernel$stdout'))
    assert_equal(['$stdout'], m.title_labels)
    assert_equal(m.label, m.title_labels.join(', '))
  end
end

require 'test/unit'
require 'bitclust'
require 'bitclust/screen'

class TestClassScreen < Test::Unit::TestCase
  SRC = <<'HERE'
= class Base < Object
base class
== Class Methods
--- base_class_method
base class method
--- shared_name
shared name
--- hidden_class_method
hidden class method
== Instance Methods
--- base_instance_method
base instance method
= module Mixin
mixin module
== Class Methods
--- mixin_class_method
mixin class method
== Instance Methods
--- mixin_instance_method
mixin instance method
= class Sub < Base
include Mixin
sub class
== Class Methods
--- sub_class_method
sub class method
--- hidden_class_method
{: undef}
== Instance Methods
--- shared_name
{: undef}

--- explanatory_method
{: nomethod}
説明のために記載しているメソッドです。

= redefine Sub
== Instance Methods
--- redefined_instance_method
redefined instance method
HERE

  def setup
    @lib, = BitClust::RRDParser.parse(SRC, 'testlib')
    datadir = File.expand_path('../data/bitclust', __dir__)
    manager = BitClust::ScreenManager.new(
      :templatedir => "#{datadir}/template.offline",
      :catalogdir => "#{datadir}/catalog",
      :encoding => 'utf-8',
      :default_encoding => 'utf-8',
      :base_url => '',
      :target_version => '3.4'
    )
    db = BitClust::MethodDatabase.dummy('version' => '3.4')
    @html = manager.class_screen(@lib.fetch_class('Sub'), :database => db).body
  end

  def test_ancestor_singleton_methods_are_displayed
    assert_include(@html, 'Baseから継承している特異メソッド')
    assert_include(@html, 'base_class_method')
  end

  def test_module_singleton_methods_are_not_inherited
    # A class does not inherit singleton methods from included modules.
    assert_not_include(@html, 'Mixinから継承している特異メソッド')
    assert_not_include(@html, 'mixin_class_method')
  end

  def test_undefined_singleton_method_is_hidden
    assert_not_include(@html, 'hidden_class_method')
  end

  def test_nomethod_method_is_listed_in_its_own_section
    assert_include(@html, '説明のための未定義メソッド')
    assert_include(@html, 'explanatory_method')
  end

  def test_nomethod_metadata_is_not_rendered_as_unknown
    assert_not_include(@html, 'UNKNOWN_META_INFO')
    assert_not_include(@html, '{:')
  end

  def test_undefined_instance_method_does_not_hide_singleton_method
    # Sub undefs the *instance* method shared_name; the inherited singleton
    # method of the same name must still be listed.
    assert_include(@html, 'shared_name')
  end

  def test_ancestor_instance_methods_include_modules
    assert_include(@html, 'Baseから継承しているメソッド')
    assert_include(@html, 'base_instance_method')
    assert_include(@html, 'Mixinから継承しているメソッド')
    assert_include(@html, 'mixin_instance_method')
  end

  def test_redefined_method_is_listed_in_its_own_section
    assert_include(@html, '再定義されたメソッド')
    assert_include(@html, 'redefined_instance_method')
  end

  def test_class_without_dynamic_include_does_not_show_dynamic_include_section
    # Regression guard: classes that never use dynamic include must render
    # exactly as before (no new headline, no leftover markers).
    assert_not_include(@html, '動的includeで追加されるメソッド')
  end
end

class TestClassScreenDynamicInclude < Test::Unit::TestCase
  SRC = <<'HERE'
= module JsonMixin
json mixin module
== Instance Methods
--- to_json
to json
== Private Instance Methods
--- hidden_json_helper
hidden json helper
= class Host < Object
host class
== Instance Methods
--- host_method
host method
= reopen Host
include JsonMixin
HERE

  def setup
    @lib, = BitClust::RRDParser.parse(SRC, 'jsonlib')
    datadir = File.expand_path('../data/bitclust', __dir__)
    manager = BitClust::ScreenManager.new(
      :templatedir => "#{datadir}/template.offline",
      :catalogdir => "#{datadir}/catalog",
      :encoding => 'utf-8',
      :default_encoding => 'utf-8',
      :base_url => '',
      :target_version => '3.4'
    )
    db = BitClust::MethodDatabase.dummy('version' => '3.4')
    @html = manager.class_screen(@lib.fetch_class('Host'), :database => db).body
  end

  def test_dynamically_included_method_is_listed_with_attribution
    assert_include(@html, '動的includeで追加されるメソッド')
    assert_include(@html, 'to_json')
    assert_include(@html, 'JsonMixin')
    assert_include(@html, '(by jsonlib)')
  end

  def test_ancestors_are_not_affected_by_dynamic_include
    assert_not_include(@lib.fetch_class('Host').ancestors.map(&:name), 'JsonMixin')
  end

  def test_private_instance_method_of_dynamically_included_module_is_hidden
    assert_not_include(@html, 'hidden_json_helper')
  end
end

class TestClassScreenAddedMethods < Test::Unit::TestCase
  SRC = <<'HERE'
= class Target < Object
target class
== Instance Methods
--- own_method
own method
= reopen Target
== Instance Methods
--- added_by_reopen
added by reopen
HERE

  def setup
    @lib, = BitClust::RRDParser.parse(SRC, 'extlib')
    datadir = File.expand_path('../data/bitclust', __dir__)
    @manager = BitClust::ScreenManager.new(
      :templatedir => "#{datadir}/template.offline",
      :catalogdir => "#{datadir}/catalog",
      :encoding => 'utf-8',
      :default_encoding => 'utf-8',
      :base_url => '',
      :target_version => '3.4'
    )
    db = BitClust::MethodDatabase.dummy('version' => '3.4')
    @html = @manager.class_screen(@lib.fetch_class('Target'), :database => db).body
  end

  # reopen 本文に直接定義されたメソッド(kind = :added)が
  # statichtml 用テンプレートの目次に出ること
  def test_added_methods_are_listed_in_offline_index
    assert_include(@html, '追加されるメソッド')
    assert_include(@html, 'added_by_reopen')
  end

  def test_class_without_added_methods_has_no_added_heading
    plain, = BitClust::RRDParser.parse(<<'PLAIN', 'extlib')
= class Plain < Object
plain class
== Instance Methods
--- plain_method
plain method
PLAIN
    db = BitClust::MethodDatabase.dummy('version' => '3.4')
    html = @manager.class_screen(plain.fetch_class('Plain'), :database => db).body
    assert_not_include(html, '追加されるメソッド')
  end
end

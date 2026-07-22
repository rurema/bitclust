require 'test/unit'
require 'bitclust'
require 'bitclust/screen'
require 'tmpdir'
require 'fileutils'

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

# bitclust#132 P3: since/until バージョンバッジが class ページ(template.offline、
# 各メソッドをインライン(compile_method 経由)で描画する側)にも出ることの確認
class TestClassScreenVersionBadges < Test::Unit::TestCase
  SRC = <<'HERE'
= class Target < Object
target class
== Instance Methods
--- own_method
own method
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
    @db = BitClust::MethodDatabase.dummy('version' => '3.4')
  end

  def test_since_badge_is_rendered_in_inlined_entry
    entry = @lib.fetch_class('Target').fetch_method(BitClust::MethodSpec.parse('Target#own_method'))
    entry.fill_since('own_method', '3.2')
    html = @manager.class_screen(@lib.fetch_class('Target'), :database => @db).body
    assert_include(html, '<span class="method-since-badge">Ruby 3.2 から</span>')
  end
end

# bitclust#132 P3: default(サーバー動的配信用)テンプレートは compiler を経由せず
# 独自に署名行を描画するので、別名(alias)ごとの署名行にそれぞれ対応する
# バッジが付く(一様化はしない)ことを個別に確認する。
#
# この template/class は @entry.inherited_method_specs を呼び、これは
# ClassEntry#_index 経由でディスク上の永続化された索引ファイルを読む。
# 他のテストのような RRDParser.parse + MethodDatabase.dummy のインメモリ
# 組では索引が存在せず ENOENT になるので、ここだけは init/update で実際に
# ディスクへコミットした本物の MethodDatabase を使う
class TestClassScreenDefaultTemplateVersionBadges < Test::Unit::TestCase
  SRC = <<'HERE'
= class Target < Object
target class
== Instance Methods
--- alias_one
--- alias_two
shared body
HERE

  def setup
    @datadir = File.expand_path('../data/bitclust', __dir__)
    @dbdir = Dir.mktmpdir('bitclust-version-badges-db')
    srcdir = Dir.mktmpdir('bitclust-version-badges-src')
    src_path = File.join(srcdir, 'testlib.rd')
    File.write(src_path, SRC)

    @db = BitClust::MethodDatabase.new(@dbdir)
    @db.init
    @db.transaction do
      @db.propset('version', '3.4')
      @db.propset('encoding', 'utf-8')
    end
    @db.transaction do
      @db.update_by_file(src_path, 'testlib')
    end
    FileUtils.rm_r(srcdir, :force => true)
  end

  def teardown
    FileUtils.rm_r(@dbdir, :force => true)
  end

  def test_per_signature_badges_attach_to_their_own_alias_line
    entry = @db.get_method(BitClust::MethodSpec.parse('Target#alias_one'))
    entry.fill_since('alias_one', '3.0')
    entry.fill_until('alias_two', '4.0')

    manager = BitClust::ScreenManager.new(
      :templatedir => "#{@datadir}/template",
      :catalogdir => "#{@datadir}/catalog",
      :encoding => 'utf-8',
      :default_encoding => 'utf-8',
      :base_url => '',
      :target_version => '3.4'
    )
    # Screen#run_template は互換 ERB を self.class にキャッシュするので、同一
    # プロセス内の他のテスト(template.offline を使う ClassScreen)と
    # templatedir が混線しないよう、この検証専用のサブクラスを介して描画する
    # (テストファイル上部のコメント、および test_method_screen.rb の同種の
    # 注記を参照。ClassScreen 本体には触れない)
    screen_class = Class.new(BitClust::ClassScreen)
    html = manager.send(:new_screen, screen_class, @db.get_class('Target'), :database => @db).body

    since_badge = '<span class="method-since-badge">Ruby 3.0 から</span>'
    until_badge = '<span class="method-until-badge">Ruby 4.0 で削除</span>'
    assert_include(html, since_badge)
    assert_include(html, until_badge)

    alias_one_pos = html.index('<code>alias_one</code>')
    alias_two_pos = html.index('<code>alias_two</code>')
    since_pos = html.index(since_badge)
    until_pos = html.index(until_badge)
    assert(alias_one_pos && alias_two_pos && since_pos && until_pos,
           'expected both signature lines and both badges to be present')
    # since は alias_one の行に付き、alias_two の行より前に来る
    assert(alias_one_pos < since_pos && since_pos < alias_two_pos,
           'the since badge must attach right after alias_one, not alias_two')
    # until は alias_two の行に付き、alias_two より後に来る
    assert(alias_two_pos < until_pos,
           'the until badge must attach after alias_two')
  end
end

# bitclust#250: Ruby 4.0 以降のドキュメントでは module function の表記を
# 独自の「.#」から「?.」に変える(表示のみ、識別子は変えない)。
#
# data/bitclust/template/class の「継承しているメソッド」一覧は
# @entry.inherited_method_specs(MethodSpec、@db を持たない値オブジェクト)を
# 直接文字列化する数少ない箇所なので、上の TestClassScreenDefaultTemplateVersionBadges
# と同じ理由で実ディスク DB を使う
class TestClassScreenModuleFunctionDisplay < Test::Unit::TestCase
  SRC = <<'HERE'
= module Mixin
mixin module
== Module Functions
--- mf
mixin module function
= class Host < Object
include Mixin
host class
== Instance Methods
--- own_method
own method
HERE

  def render(version)
    datadir = File.expand_path('../data/bitclust', __dir__)
    dbdir = Dir.mktmpdir('bitclust-module-function-display-db')
    srcdir = Dir.mktmpdir('bitclust-module-function-display-src')
    begin
      src_path = File.join(srcdir, 'testlib.rd')
      File.write(src_path, SRC)

      db = BitClust::MethodDatabase.new(dbdir)
      db.init
      db.transaction do
        db.propset('version', version)
        db.propset('encoding', 'utf-8')
      end
      db.transaction do
        db.update_by_file(src_path, 'testlib')
      end

      manager = BitClust::ScreenManager.new(
        :templatedir => "#{datadir}/template",
        :catalogdir => "#{datadir}/catalog",
        :encoding => 'utf-8',
        :default_encoding => 'utf-8',
        :base_url => '',
        :target_version => version
      )
      # See TestClassScreenDefaultTemplateVersionBadges above for the general
      # background: Screen#run_template caches the compiled ERB body on the
      # *class*, keyed only by method name. A plain anonymous subclass is not
      # sufficient isolation here, though: if BitClust::ClassScreen itself
      # was already compiled for a different templatedir (offline) by some
      # other test earlier in this same process -- order-dependent, since
      # TestClassScreen above uses BitClust::ClassScreen directly, with no
      # subclass -- then `respond_to?(:class_template)` is already true via
      # *inheritance*, and the subclass would silently reuse that stale
      # compiled method instead of compiling its own. So compile directly
      # onto screen_class ourselves, before Screen#run_template ever gets a
      # chance to check: our own method then always wins by normal Ruby
      # method resolution, regardless of what BitClust::ClassScreen has.
      screen_class = Class.new(BitClust::ClassScreen)
      repo = BitClust::TemplateRepository.new("#{datadir}/template")
      ERB.new(repo.load('class')).def_method(screen_class, 'class_template', 'class.erb')
      manager.send(:new_screen, screen_class, db.get_class('Host'), :database => db).body
    ensure
      FileUtils.rm_r(srcdir, :force => true)
      FileUtils.rm_r(dbdir, :force => true)
    end
  end

  def test_inherited_module_function_shows_dot_hash_before_4_0
    html = render('3.4')
    assert_include(html, '.#mf')
    assert_not_include(html, '?.mf')
  end

  def test_inherited_module_function_switches_to_question_dot_at_4_0
    html = render('4.0')
    assert_include(html, '?.mf')
    assert_not_include(html, '.#mf')
  end
end

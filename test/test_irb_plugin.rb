# frozen_string_literal: true
require 'test/unit'
require 'tmpdir'
require 'fileutils'
require 'stringio'
require 'bitclust'
require 'bitclust/methoddatabase'
require 'bitclust/searcher'

# bitclust-irb gem の irb コマンド(refe)。
#
# テストリスト:
# [x] TerminalView が io: に出力する(既定は従来どおり $stdout)
# [x] Irb.lookup がメソッドを検索して整形結果を io へ書く
# [x] Irb.lookup がクラスも引ける
# [x] 空のパターンは使い方を表示して例外にしない
# [x] 見つからないパターンはメッセージを io へ書いて例外にしない
# [x] require で IRB::Command::Base のサブクラスとして登録される
class TestBitClustIrbPlugin < Test::Unit::TestCase
  FOO_MD = <<~'MD'
    ---
    library: foo
    ---
    # class Foo < Object

    クラスの説明。

    ## Instance Methods

    ### def bar -> nil

    bar の説明。
  MD

  def build_markdown_db(dir)
    api = File.join(dir, 'manual', 'api')
    FileUtils.mkdir_p(File.join(api, 'foo'))
    File.write(File.join(api, 'foo.md'), "---\ntype: library\n---\nfoo ライブラリ。\n")
    File.write(File.join(api, 'foo', 'Foo.md'), FOO_MD)
    prefix = File.join(dir, 'db')
    db = BitClust::MethodDatabase.new(prefix)
    db.init
    db.transaction do
      db.propset('version', '3.4')
      db.propset('encoding', 'utf-8')
    end
    db.transaction do
      db.update_by_markdowntree(api)
    end
    BitClust::MethodDatabase.new(prefix)
  end

  def with_db(&block)
    Dir.mktmpdir do |dir|
      yield build_markdown_db(dir)
    end
  end

  def test_terminal_view_writes_to_given_io
    out = StringIO.new
    view = BitClust::TerminalView.new(BitClust::Plain.new, {}, io: out)
    view.send(:puts, 'hello')
    assert_equal("hello\n", out.string)
  end

  def test_lookup_method
    require 'bitclust/irb'
    with_db do |db|
      out = StringIO.new
      BitClust::Irb.lookup('Foo#bar', db: db, io: out)
      assert_match(/Foo#bar/, out.string)
      assert_match(/bar の説明。/, out.string)
    end
  end

  def test_lookup_class
    require 'bitclust/irb'
    with_db do |db|
      out = StringIO.new
      BitClust::Irb.lookup('Foo', db: db, io: out)
      assert_match(/class Foo < Object/, out.string)
      assert_match(/クラスの説明。/, out.string)
    end
  end

  def test_lookup_empty_pattern_shows_usage
    require 'bitclust/irb'
    with_db do |db|
      out = StringIO.new
      assert_nothing_raised do
        BitClust::Irb.lookup('', db: db, io: out)
      end
      assert_match(/refe/, out.string)
    end
  end

  def test_lookup_not_found_reports_instead_of_raising
    require 'bitclust/irb'
    with_db do |db|
      out = StringIO.new
      assert_nothing_raised do
        BitClust::Irb.lookup('NoSuchClass#no_such_method', db: db, io: out)
      end
      assert_match(/no such method/, out.string)
    end
  end

  def test_command_is_registered_for_irb
    begin
      require 'irb/command'
    rescue LoadError
      omit 'irb >= 1.13 is not available'
    end
    require 'bitclust/irb'
    assert(BitClust::Irb::RefeCommand < ::IRB::Command::Base)
    assert_match(/るりま|リファレンス/, BitClust::Irb::RefeCommand.description)
  end
end

# frozen_string_literal: true
require 'test/unit'
require 'tmpdir'
require 'fileutils'
require 'stringio'
require 'json'
require 'bitclust'
require 'bitclust/methoddatabase'
require 'bitclust/searcher'
require 'bitclust/irb'

# bitclust-irb gem の irb コマンド(refe)。リモート検索そのものは
# test_remote.rb で検証する。
#
# テストリスト:
# [x] TerminalView が io: に出力する(既定は従来どおり $stdout)
# [x] Irb.lookup がメソッドを検索して整形結果を io へ書く
# [x] Irb.lookup がクラスも引ける
# [x] 空のパターンは使い方を表示して例外にしない
# [x] 見つからないパターンはメッセージを io へ書いて例外にしない
# [x] require で IRB::Command::Base のサブクラスとして登録される
# [x] Searcher#local_database? は既定の場所に DB が無ければ false・あれば true
# [x] Irb.lookup: db が与えられていれば remote を使わない
# [x] Irb.lookup: ローカル DB が無ければ remote で検索する
# [x] Irb.lookup: remote が nil なら bitclust setup を案内する
# [x] refe の CLI(Searcher#exec)も DB が無ければ remote で検索する
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

  BASE_URL = 'https://docs.ruby-lang.org/ja/latest/'
  INDEX_JS = "var search_data = #{JSON.generate(index: [
    { name: 'String', full_name: 'String', type: 'class', path: 'class/String.html' },
    { name: 'gsub', full_name: 'String#gsub', type: 'instance_method', path: 'method/String/i/gsub.html' },
  ])};\n"
  PAGES = {
    'js/search_data.js' => INDEX_JS,
    'method/String/i/gsub.md' => "# String#gsub\n\n置き換えます。\n",
  }.freeze

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

  # 既定の DB 探索(環境変数・設定ファイル)がどれも当たらない状態
  DB_ENV_KEYS = %w[REFE2_SERVER BITCLUST_SERVER REFE2_DATADIR BITCLUST_DATADIR
                   HOME XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME].freeze

  def without_local_db
    saved = DB_ENV_KEYS.to_h {|k| [k, ENV[k]] }
    Dir.mktmpdir do |home|
      DB_ENV_KEYS.each {|k| ENV.delete(k) }
      ENV['HOME'] = home
      yield home
    end
  ensure
    saved.each {|k, v| v ? ENV[k] = v : ENV.delete(k) }
  end

  def fake_remote(dir, pages = PAGES)
    fetcher = lambda do |uri, _headers|
      rel = uri.to_s.delete_prefix(BASE_URL)
      pages.key?(rel) ? [200, pages[rel].dup] : [404, '']
    end
    BitClust::Remote.new(base_url: BASE_URL, fetcher: fetcher, cache_dir: File.join(dir, 'cache'))
  end

  def never_remote(dir)
    BitClust::Remote.new(base_url: BASE_URL, cache_dir: File.join(dir, 'cache'),
                         fetcher: ->(_uri, _headers) { flunk 'remote must not be used' })
  end

  def test_terminal_view_writes_to_given_io
    out = StringIO.new
    view = BitClust::TerminalView.new(BitClust::Plain.new, {}, io: out)
    view.send(:puts, 'hello')
    assert_equal("hello\n", out.string)
    assert_same(out, view.io)
    assert_same($stdout, BitClust::TerminalView.new(BitClust::Plain.new, {}).io)
  end

  def test_lookup_method
    with_db do |db|
      out = StringIO.new
      BitClust::Irb.lookup('Foo#bar', db: db, io: out)
      assert_match(/Foo#bar/, out.string)
      assert_match(/bar の説明。/, out.string)
    end
  end

  def test_lookup_class
    with_db do |db|
      out = StringIO.new
      BitClust::Irb.lookup('Foo', db: db, io: out)
      assert_match(/class Foo < Object/, out.string)
      assert_match(/クラスの説明。/, out.string)
    end
  end

  def test_lookup_empty_pattern_shows_usage
    with_db do |db|
      out = StringIO.new
      assert_nothing_raised do
        BitClust::Irb.lookup('', db: db, io: out)
      end
      assert_match(/refe/, out.string)
    end
  end

  def test_lookup_not_found_reports_instead_of_raising
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
    assert(BitClust::Irb::RefeCommand < ::IRB::Command::Base)
    assert_match(/るりま|リファレンス/, BitClust::Irb::RefeCommand.description)
  end

  def test_searcher_local_database_p
    without_local_db do
      assert_false(BitClust::Searcher.new.local_database?)
      with_db do |db|
        ENV['BITCLUST_DATADIR'] = db.instance_variable_get(:@prefix)
        assert_true(BitClust::Searcher.new.local_database?)
      end
    end
  end

  def test_lookup_uses_local_db_when_given
    with_db do |db|
      Dir.mktmpdir do |dir|
        out = StringIO.new
        BitClust::Irb.lookup('Foo#bar', db: db, io: out, remote: never_remote(dir))
        assert_match(/bar の説明。/, out.string)
      end
    end
  end

  def test_lookup_falls_back_to_remote_without_local_db
    without_local_db do |home|
      out = StringIO.new
      BitClust::Irb.lookup('String#gsub', io: out, remote: fake_remote(home))
      assert_match(/置き換えます。/, out.string)
      assert_match(%r{method/String/i/gsub\.html}, out.string)
    end
  end

  def test_lookup_without_remote_and_local_db_shows_setup_hint
    without_local_db do
      out = StringIO.new
      assert_nothing_raised do
        BitClust::Irb.lookup('String#gsub', io: out, remote: nil)
      end
      assert_match(/bitclust setup/, out.string)
    end
  end

  def test_refe_cli_falls_back_to_remote_without_local_db
    without_local_db do |home|
      out = StringIO.new
      searcher = BitClust::Searcher.new
      searcher.remote = fake_remote(home)
      searcher.parse(%w[String#gsub])
      view = BitClust::TerminalView.new(BitClust::Plain.new, {}, io: out)
      searcher.run_query(nil, %w[String#gsub], view)
      assert_match(/置き換えます。/, out.string)
    end
  end
end

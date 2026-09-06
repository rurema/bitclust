# frozen_string_literal: true
require 'test/unit'
require 'tmpdir'
require 'fileutils'
require 'stringio'
require 'json'
require 'time'
require 'bitclust'
require 'bitclust/searcher'
require 'bitclust/remote'

# ローカル DB が無いときのリモート検索(docs.ruby-lang.org の検索索引
# search_data.js と Markdown 配信をキャッシュ付きで使う)。
#
# テストリスト:
# Cache:
# [x] 未取得なら GET して保存し本文を返す
# [x] 1 日以内のキャッシュはネットワークに行かずに返す
# [x] 1 日以上古ければ If-Modified-Since 付きで確認し、304 なら touch して返す
# [x] 200 なら上書き保存する
# [x] 404 はキャッシュを消して nil
# [x] 接続エラー時にキャッシュがあれば古くても返して stale にする。無ければ例外
# [x] 本文は UTF-8 として扱う
# Index:
# [x] search_data.js を読んでクラス・メソッド(path から クラス・種別・名前)・ライブラリ・関数にする
# [x] メソッド指定は refe と同じ規則(クラスは大小無視の前方一致→完全一致、種別は typemark)
# [x] Kernel.#printf と Kernel?.printf は同じ module function。Kernel.printf は特異メソッドなので該当なし
# [x] 種別なし 2 語は全種別から探す
# [x] 3 語の種別は typemark として検査する(不正・$ は InvalidKey)
# [x] $ 始まりは特殊変数
# [x] A::B はクラス → 定数の順
# [x] 大文字 1 語はクラス → メソッド名の順、小文字 1 語はメソッド名 → クラス → ライブラリ → 関数の順
# [x] 語なしは全クラス、class_only: はクラスだけ
# [x] document・heading は検索対象にしない
# Remote#lookup:
# [x] 1 件に決まれば .md を取得して本文と出典 URL を書く
# [x] 複数なら名前一覧(line: なら 1 行 1 件、describe_all: なら全件の本文)
# [x] 見つからなければメッセージと検索ページ URL
# [x] 索引が取れずキャッシュも無ければメッセージだけ(例外にしない)
# [x] Remote.default は BITCLUST_REMOTE_URL が指定があればその URL
# [x] Remote.default は BITCLUST_REMOTE_URL が none(大小無視)か空なら nil(Windows では空の環境変数を作れない)
class TestRemote < Test::Unit::TestCase
  BASE_URL = 'https://docs.ruby-lang.org/ja/latest/'

  INDEX = {
    index: [
      { name: 'String', full_name: 'String', type: 'class', path: 'class/String.html' },
      { name: 'StringIO', full_name: 'StringIO', type: 'class', path: 'class/StringIO.html' },
      { name: 'Kernel', full_name: 'Kernel', type: 'module', path: 'class/Kernel.html' },
      { name: 'File', full_name: 'File', type: 'class', path: 'class/File.html' },
      { name: 'File::Stat', full_name: 'File::Stat', type: 'class', path: 'class/File=3a=3aStat.html' },
      { name: 'ARGF', full_name: 'ARGF', type: 'object', path: 'class/ARGF.html' },
      { name: 'gsub', full_name: 'String#gsub', type: 'instance_method', path: 'method/String/i/gsub.html' },
      { name: 'gsub!', full_name: 'String#gsub!', type: 'instance_method', path: 'method/String/i/gsub=21.html' },
      { name: 'size', full_name: 'String#size', type: 'instance_method', path: 'method/String/i/size.html' },
      { name: 'size', full_name: 'StringIO#size', type: 'instance_method', path: 'method/StringIO/i/size.html' },
      { name: 'size', full_name: 'File#size', type: 'instance_method', path: 'method/File/i/size.html' },
      { name: 'size', full_name: 'File.size', type: 'class_method', path: 'method/File/s/size.html', match_name: 'File::size' },
      { name: 'new', full_name: 'String.new', type: 'class_method', path: 'method/String/s/new.html', match_name: 'String::new' },
      { name: 'printf', full_name: 'Kernel?.printf', type: 'class_method', path: 'method/Kernel/m/printf.html', match_name: 'Kernel::#printf' },
      { name: 'SEPARATOR', full_name: 'File::SEPARATOR', type: 'constant', path: 'method/File/c/SEPARATOR.html' },
      { name: '$stdout', full_name: '$stdout', type: 'variable', path: 'method/Kernel/v/stdout.html' },
      { name: 'json', full_name: 'json', type: 'library', path: 'library/json.html' },
      { name: 'net/http', full_name: 'net/http', type: 'library', path: 'library/net=2fhttp.html' },
      { name: 'rb_str_new', full_name: 'rb_str_new', type: 'function', path: 'function/rb_str_new.html' },
      { name: 'ReFe', full_name: 'ReFe', type: 'document', path: 'doc/ReFe.html' },
      { name: 'Zzz', full_name: 'Zzz (Ruby用語集)', type: 'heading', path: 'doc/glossary.html#Zzz' },
    ],
  }.freeze
  INDEX_JS = "var search_data = #{JSON.generate(INDEX)};\n"

  PAGES = {
    'js/search_data.js' => INDEX_JS,
    'method/String/i/gsub.md' => "# String#gsub\n\n### def gsub(pattern, replace) -> String\n\n置き換えます。\n",
    'method/String/i/size.md' => "# String#size\n\n長さです。\n",
    'method/File/s/size.md' => "# File.size\n\nサイズです。\n",
    'method/File/i/size.md' => "# File#size\n\nサイズです。\n",
    'method/StringIO/i/size.md' => "# StringIO#size\n\nサイズです。\n",
    'class/String.md' => "# class String < Object\n\n文字列のクラスです。\n",
    'library/json.md' => "# library json\n\nJSON です。\n",
  }.freeze

  T0 = Time.utc(2026, 9, 2, 12, 0, 0)

  def setup
    @dir = Dir.mktmpdir
    @saved_env = ENV['BITCLUST_REMOTE_URL']
    ENV.delete('BITCLUST_REMOTE_URL')
  end

  def teardown
    FileUtils.rm_rf(@dir)
    @saved_env ? ENV['BITCLUST_REMOTE_URL'] = @saved_env : ENV.delete('BITCLUST_REMOTE_URL')
  end

  # pages: base_url からの相対パス => 本文。無いパスは 404。requests に
  # [URL, ヘッダ] を記録する
  def fake_fetcher(pages = PAGES, requests = [])
    lambda do |uri, headers|
      requests << [uri.to_s, headers]
      rel = uri.to_s.delete_prefix(BASE_URL)
      pages.key?(rel) ? [200, pages[rel].dup] : [404, '<Error><Code>AccessDenied</Code></Error>']
    end
  end

  def remote(pages = PAGES, requests = [], now: T0)
    BitClust::Remote.new(base_url: BASE_URL, fetcher: fake_fetcher(pages, requests),
                         cache_dir: @dir, clock: -> { now })
  end

  def index
    BitClust::Remote::Index.parse(INDEX_JS)
  end

  def names(entries)
    entries.map(&:full_name)
  end

  def cache(fetcher, now: T0)
    BitClust::Remote::Cache.new(dir: @dir, fetcher: fetcher, clock: -> { now })
  end

  def gsub_uri
    URI("#{BASE_URL}method/String/i/gsub.md")
  end

  # --- Cache ---

  def test_cache_fetches_and_stores
    requests = []
    hit = cache(fake_fetcher(PAGES, requests)).fetch(gsub_uri)
    assert_match(/置き換えます。/, hit.body)
    assert_false(hit.stale)
    assert_equal([[gsub_uri.to_s, {}]], requests)
    path = File.join(@dir, 'docs.ruby-lang.org', 'ja', 'latest', 'method', 'String', 'i', 'gsub.md')
    assert_equal(PAGES['method/String/i/gsub.md'], File.read(path, encoding: 'UTF-8'))
    assert_equal(T0, File.mtime(path))
  end

  def test_cache_reuses_fresh_copy_without_network
    requests = []
    c = cache(fake_fetcher(PAGES, requests))
    c.fetch(gsub_uri)
    later = cache(fake_fetcher(PAGES, requests), now: T0 + 23 * 3600)
    hit = later.fetch(gsub_uri)
    assert_match(/置き換えます。/, hit.body)
    assert_equal(1, requests.size)
  end

  def test_cache_revalidates_old_copy_with_if_modified_since
    requests = []
    cache(fake_fetcher(PAGES, requests)).fetch(gsub_uri)
    not_modified = lambda do |uri, headers|
      requests << [uri.to_s, headers]
      [304, '']
    end
    now = T0 + 25 * 3600
    hit = cache(not_modified, now: now).fetch(gsub_uri)
    assert_match(/置き換えます。/, hit.body)
    assert_false(hit.stale)
    assert_equal(2, requests.size)
    assert_equal({ 'If-Modified-Since' => T0.httpdate }, requests.last[1])
    assert_equal(now, File.mtime(hit.path))
  end

  def test_cache_overwrites_on_200
    cache(fake_fetcher(PAGES)).fetch(gsub_uri)
    updated = PAGES.merge('method/String/i/gsub.md' => "# String#gsub\n\n新しい説明。\n")
    hit = cache(fake_fetcher(updated), now: T0 + 2 * 86400).fetch(gsub_uri)
    assert_match(/新しい説明。/, hit.body)
    assert_equal("# String#gsub\n\n新しい説明。\n", File.read(hit.path, encoding: 'UTF-8'))
  end

  def test_cache_removes_copy_on_404
    c = cache(fake_fetcher(PAGES))
    hit = c.fetch(gsub_uri)
    assert_nil(cache(fake_fetcher({}), now: T0 + 2 * 86400).fetch(gsub_uri))
    assert_false(File.exist?(hit.path))
    assert_nil(cache(fake_fetcher({})).fetch(URI("#{BASE_URL}class/Nope.md")))
  end

  def test_cache_serves_stale_copy_when_offline
    failing = ->(_uri, _headers) { raise SocketError, 'getaddrinfo failed' }
    assert_raise(SocketError) { cache(failing).fetch(gsub_uri) }
    cache(fake_fetcher(PAGES)).fetch(gsub_uri)
    hit = cache(failing, now: T0 + 2 * 86400).fetch(gsub_uri)
    assert_match(/置き換えます。/, hit.body)
    assert_true(hit.stale)
  end

  def test_cache_body_is_utf8
    binary = { 'class/String.md' => "# class String < Object\n\n文字列のクラスです。\n".b }
    hit = cache(fake_fetcher(binary)).fetch(URI("#{BASE_URL}class/String.md"))
    assert_equal(Encoding::UTF_8, hit.body.encoding)
    assert_true(hit.body.valid_encoding?)
    again = cache(fake_fetcher({})).fetch(URI("#{BASE_URL}class/String.md"))
    assert_equal(Encoding::UTF_8, again.body.encoding)
    assert_match(/文字列のクラスです。/, again.body)
  end

  # --- Index ---

  def test_index_parses_entries
    i = index
    e = i.search(%w[String#gsub]).first
    assert_equal(['String', 'i', 'gsub', 'method/String/i/gsub.html'], [e.klass, e.typechar, e.name, e.path])
    assert_equal(%w[File.size], names(i.search(%w[File.size])))
    assert_equal(%w[net/http], names(i.search(%w[net/http])))
  end

  def test_index_method_spec_follows_refe_rules
    i = index
    assert_equal(%w[String#gsub], names(i.search(%w[String#gsub])))
    assert_equal(%w[String#gsub], names(i.search(%w[str#gsub])))
    assert_equal(%w[String#gsub String#gsub!], names(i.search(%w[Str#gs])))
    assert_equal(%w[String#gsub!], names(i.search(%w[String#gsub!])))
    assert_equal(%w[String.new], names(i.search(%w[String.new])))
    assert_equal(%w[String#gsub], names(i.search(%w[String,gsub])))
    assert_equal([], names(i.search(%w[String#nope])))
    assert_equal([], names(i.search(%w[Nope#gsub])))
  end

  def test_index_module_function_typemarks
    i = index
    assert_equal(%w[Kernel?.printf], names(i.search(%w[Kernel.#printf])))
    assert_equal(%w[Kernel?.printf], names(i.search(%w[Kernel?.printf])))
    assert_equal([], names(i.search(%w[Kernel.printf])))
  end

  def test_index_two_words_search_all_types
    i = index
    assert_equal(%w[File#size File.size], names(i.search(%w[File size])))
    assert_equal(%w[String#size StringIO#size], names(i.search(%w[str size])))
    assert_equal([], names(i.search(%w[String nope])))
  end

  def test_index_three_words_check_typemark
    i = index
    assert_equal(%w[File.size], names(i.search(%w[File . size])))
    assert_equal(%w[File#size], names(i.search(%w[File # size])))
    assert_raise(BitClust::InvalidKey) { i.search(%w[File x size]) }
    assert_raise(BitClust::InvalidKey) { i.search(%w[Kernel $ stdout]) }
    assert_raise(BitClust::InvalidKey) { i.search(%w[a b c d]) }
  end

  def test_index_special_variable
    i = index
    assert_equal(%w[$stdout], names(i.search(%w[$stdout])))
    assert_equal(%w[$stdout], names(i.search(%w[$std])))
    assert_equal([], names(i.search(%w[$nope])))
  end

  def test_index_scoped_name_prefers_class_then_constant
    i = index
    assert_equal(%w[File::Stat], names(i.search(%w[File::Stat])))
    assert_equal(%w[File::SEPARATOR], names(i.search(%w[File::SEPARATOR])))
    assert_equal([], names(i.search(%w[File::NOPE])))
  end

  def test_index_single_word_order
    i = index
    assert_equal(%w[String], names(i.search(%w[String])))
    assert_equal(%w[String StringIO], names(i.search(%w[S])))
    assert_equal(%w[File#size File.size String#size StringIO#size], names(i.search(%w[size])).sort)
    assert_equal(%w[Kernel?.printf], names(i.search(%w[printf])))
    assert_equal(%w[json], names(i.search(%w[json])))
    assert_equal(%w[rb_str_new], names(i.search(%w[rb_str_new])))
    assert_equal(%w[ARGF], names(i.search(%w[argf])))
    assert_equal([], names(i.search(%w[nothing])))
  end

  def test_index_no_words_and_class_only
    i = index
    assert_equal(%w[ARGF File File::Stat Kernel String StringIO], names(i.search([])).sort)
    assert_equal(%w[String StringIO], names(i.search(%w[S], class_only: true)))
    assert_equal([], names(i.search(%w[size], class_only: true)))
    assert_raise(BitClust::InvalidKey) { i.search(%w[a b], class_only: true) }
  end

  def test_index_ignores_documents_and_headings
    i = index
    assert_equal([], names(i.search(%w[ReFe])))
    assert_equal([], names(i.search(%w[Zzz])))
  end

  # --- Remote#lookup ---

  def test_lookup_single_hit_shows_page_with_source_url
    requests = []
    out = StringIO.new
    assert_true(remote(PAGES, requests).lookup(%w[String#gsub], out))
    assert_match(/\A# String#gsub$/, out.string)
    assert_match(/置き換えます。/, out.string)
    assert_match(%r{^https://docs.ruby-lang.org/ja/latest/method/String/i/gsub.html$}, out.string)
    assert_equal(["#{BASE_URL}js/search_data.js", "#{BASE_URL}method/String/i/gsub.md"], requests.map(&:first))
  end

  def test_lookup_multiple_hits_lists_names
    out = StringIO.new
    assert_true(remote.lookup(%w[size], out))
    assert_equal("File#size File.size String#size StringIO#size \n", out.string)
    out = StringIO.new
    remote.lookup(%w[size], out, line: true)
    assert_equal("File#size\nFile.size\nString#size\nStringIO#size\n", out.string)
    out = StringIO.new
    remote.lookup(%w[size], out, describe_all: true)
    assert_match(/# File#size.*# File\.size.*# String#size.*# StringIO#size/m, out.string)
  end

  def test_lookup_single_hit_with_line_prints_name_only
    out = StringIO.new
    remote.lookup(%w[String#gsub], out, line: true)
    assert_equal("String#gsub\n", out.string)
  end

  def test_lookup_class_only
    out = StringIO.new
    remote.lookup(%w[String], out, class_only: true)
    assert_match(/文字列のクラスです。/, out.string)
  end

  def test_lookup_not_found_shows_search_url
    out = StringIO.new
    assert_nothing_raised do
      assert_false(remote.lookup(%w[NoSuchClass#nope], out))
    end
    assert_match(/no such method: NoSuchClass#nope/, out.string)
    assert_match(%r{https://docs.ruby-lang.org/ja/search/\?q=NoSuchClass%23nope}, out.string)
    out = StringIO.new
    assert_false(remote.lookup(%w[Nope], out, class_only: true))
    assert_match(/no such class: Nope/, out.string)
  end

  def test_lookup_without_index_reports_instead_of_raising
    failing = BitClust::Remote.new(base_url: BASE_URL, cache_dir: @dir, clock: -> { T0 },
                                   fetcher: ->(_uri, _headers) { raise SocketError, 'getaddrinfo failed' })
    out = StringIO.new
    assert_nothing_raised do
      assert_false(failing.lookup(%w[String#gsub], out))
    end
    assert_match(/docs\.ruby-lang\.org/, out.string)
    assert_match(/getaddrinfo/, out.string)
    assert_match(/bitclust setup/, out.string)
  end

  def test_lookup_uses_cached_index_when_offline
    remote.lookup(%w[String#gsub], StringIO.new)
    failing = BitClust::Remote.new(base_url: BASE_URL, cache_dir: @dir, clock: -> { T0 + 3 * 86400 },
                                   fetcher: ->(_uri, _headers) { raise SocketError, 'getaddrinfo failed' })
    out = StringIO.new
    assert_true(failing.lookup(%w[String#gsub], out))
    assert_match(/置き換えます。/, out.string)
    assert_match(/オフライン/, out.string)
  end

  def test_default_follows_environment
    assert_equal(BitClust::Remote::DEFAULT_BASE_URL, BitClust::Remote.default.base_url)
    ENV['BITCLUST_REMOTE_URL'] = 'http://localhost:10080/ja/latest'
    assert_equal('http://localhost:10080/ja/latest/', BitClust::Remote.default.base_url)
  end

  # Windows のシェル(cmd.exe・PowerShell)では空の環境変数を作れないので、
  # 無効化は "none" でもできる
  def test_default_is_disabled_by_none_or_empty
    %w[none NONE None].each do |value|
      ENV['BITCLUST_REMOTE_URL'] = value
      assert_nil(BitClust::Remote.default, value)
    end
    ENV['BITCLUST_REMOTE_URL'] = ''
    assert_nil(BitClust::Remote.default)
    ENV['BITCLUST_REMOTE_URL'] = 'http://none.example/'
    assert_equal('http://none.example/', BitClust::Remote.default.base_url)
  end
end

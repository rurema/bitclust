# frozen_string_literal: true
#
# ローカル DB が無い環境向けのリモート検索。docs.ruby-lang.org の検索索引
# (js/search_data.js = SearchIndexGenerator の生成物)を refe と同じ規則で
# 引いて候補を絞り、1 件に決まれば Markdown 配信(/ja/latest/ 配下の .md =
# statichtml --markdown-output の生成物)から本文を取得して表示する。
# 取得したものは UserDirs.cache_home 配下にキャッシュし、1 日以内はそのまま、
# それより古ければ If-Modified-Since で確認してから使う。接続できなければ
# 古いキャッシュで動く。名前一覧の表示には searcher.rb の TerminalView を
# 使う(このファイルは searcher.rb から require される)。

require 'json'
require 'net/http'
require 'openssl'
require 'time'
require 'uri'
require 'fileutils'
require 'bitclust/version'
require 'bitclust/nameutils'
require 'bitclust/exception'
require 'bitclust/user_dirs'

module BitClust
  class Remote
    include NameUtils

    DEFAULT_BASE_URL = 'https://docs.ruby-lang.org/ja/latest/'
    SEARCH_URL = 'https://docs.ruby-lang.org/ja/search/'
    INDEX_PATH = 'js/search_data.js'
    ENV_KEY = 'BITCLUST_REMOTE_URL'

    # 200/304/404 以外の応答(キャッシュも無いとき)
    class HTTPError < StandardError; end

    NETWORK_ERRORS = [SocketError, IOError, SystemCallError, Timeout::Error,
                      OpenSSL::SSL::SSLError, Net::ProtocolError, HTTPError].freeze

    # BITCLUST_REMOTE_URL にこの値(大小無視)を設定するとリモート検索をしない。
    # 空文字列でも同じだが、Windows のシェル(cmd.exe・PowerShell)では
    # 空の環境変数を作れない(削除になる)ので、無効化の値を別に用意する
    DISABLED_VALUE = 'none'

    # 既定の取得元。環境変数 BITCLUST_REMOTE_URL があればそれを使い、
    # DISABLED_VALUE か空文字列ならリモート検索をしない(nil)
    def self.default
      url = ENV.fetch(ENV_KEY, DEFAULT_BASE_URL)
      url.empty? || url.casecmp?(DISABLED_VALUE) ? nil : new(base_url: url)
    end

    attr_reader :base_url

    # fetcher は (URI, ヘッダの Hash) を受け取って [ステータス, 本文] を返す
    # 呼び出し可能オブジェクト。省略時は Net::HTTP。cache_dir はキャッシュの
    # 置き場所、clock は現在時刻を返す Proc(テスト用)
    def initialize(base_url: DEFAULT_BASE_URL, fetcher: nil,
                   cache_dir: UserDirs.cache_home, clock: nil)
      @base_url = base_url.end_with?('/') ? base_url : "#{base_url}/"
      clock ||= -> { Time.now }
      if fetcher
        @http = nil
        @cache = Cache.new(dir: cache_dir.to_s, fetcher: fetcher, clock: clock)
      else
        http = HttpFetcher.new
        @http = http
        @cache = Cache.new(dir: cache_dir.to_s, fetcher: http, clock: clock)
      end
    end

    # refe と同じ引数 words で検索して結果を io へ書く。何か表示できれば true。
    # 見つからない・取得できない場合はメッセージを書いて false(例外にしない)
    def lookup(words, io, describe_all: false, line: false, class_only: false)
      entries = load_index.search(words, class_only: class_only).sort_by(&:full_name)
      if entries.empty?
        io.puts not_found_message(words, class_only)
        io.puts "検索ページ: #{search_url(words)}" unless words.empty?
        return false
      end
      view = TerminalView.new(Plain.new, { describe_all: describe_all, line: line, encoding: nil }, io: io)
      if line || (entries.size > 1 && !describe_all)
        view.print_names(entries.map(&:full_name))
      else
        entries.each {|e| show_page(e, io) }
        io.puts '(docs.ruby-lang.org から取得しました。手元で検索するには bitclust setup で DB を作成してください)'
      end
      true
    rescue *NETWORK_ERRORS => err
      io.puts "docs.ruby-lang.org に接続できず、キャッシュもありません (#{err.class}: #{err.message})"
      io.puts 'オフラインで使うには bitclust setup で DB を作成してください。'
      false
    ensure
      @http&.close
    end

    def search_url(words)
      "#{SEARCH_URL}?q=#{URI.encode_www_form_component(words.join(' '))}"
    end

    # 同じキャッシュファイル(パスと mtime)なら解析済みの索引を使い回す
    def self.index_for(path, body)
      key = [path, File.mtime(path)]
      memo = @index_memo
      return memo[1] if memo && memo[0] == key
      index = Index.parse(body)
      @index_memo = [key, index]
      index
    end

    private

    def load_index
      hit = @cache.fetch(URI("#{@base_url}#{INDEX_PATH}"))
      raise HTTPError, "#{INDEX_PATH} not found" unless hit
      self.class.index_for(hit.path, hit.body)
    end

    def show_page(entry, io)
      html_url = "#{@base_url}#{entry.path}"
      hit = @cache.fetch(URI("#{@base_url}#{entry.path.sub(/\.html\z/, '.md')}"))
      if hit
        io.puts hit.body
        io.puts
        io.puts '---'
        io.puts html_url
        if hit.stale
          io.puts "(オフライン: #{File.mtime(hit.path).strftime('%Y-%m-%d %H:%M')} 取得のキャッシュを表示しています)"
        end
      else
        io.puts "#{entry.full_name}: ページを取得できませんでした (#{html_url})"
      end
      io.puts
    end

    def not_found_message(words, class_only)
      pattern = words.join(' ')
      if class_only
        "no such class: #{pattern}"
      elsif words.size >= 2
        "no such method in #{words.first}: #{words.last}"
      elsif pattern.match?(/[\#,]\.|\.[\#,]|[\#\.\,]/)
        "no such method: #{pattern}"
      else
        "no such class or method: #{pattern}"
      end
    end

    # 索引の 1 エントリ。メソッド系(instance_method・class_method・constant・
    # variable)は path("method/<クラス>/<種別 1 文字>/<名前>.html")から
    # klass と typechar を持つ
    class Entry
      attr_reader :name, :full_name, :type, :path
      attr_accessor :klass, :typechar

      def initialize(name:, full_name:, type:, path:, klass: nil, typechar: nil)
        @name = name
        @full_name = full_name
        @type = type
        @path = path
        @klass = klass
        @typechar = typechar
      end
    end

    # search_data.js を読んで refe と同じ規則で検索する
    class Index
      include NameUtils

      CLASS_TYPES = %w[class module object].freeze
      METHOD_TYPES = %w[instance_method class_method constant variable].freeze
      METHOD_PATH_RE = %r{\Amethod/([^/]+)/([a-z])/([^/]+)\.html\z}

      def self.parse(js)
        json = js.sub(/\A\s*var\s+search_data\s*=\s*/, '').sub(/;\s*\z/, '')
        data = JSON.parse(json)
        entries = data['index'].map {|h|
          entry = Entry.new(name: h['name'], full_name: h['full_name'], type: h['type'], path: h['path'])
          if METHOD_TYPES.include?(entry.type) && (m = METHOD_PATH_RE.match(entry.path))
            entry.klass = NameUtils.decodename_url(m[1] || raise)
            entry.typechar = m[2]
          end
          entry
        }
        new(entries)
      end

      def initialize(entries)
        @classes = entries.select {|e| CLASS_TYPES.include?(e.type) }
        @methods = entries.select {|e| METHOD_TYPES.include?(e.type) && e.klass }
        @libraries = entries.select {|e| e.type == 'library' }
        @functions = entries.select {|e| e.type == 'function' }
      end

      # words は refe の引数(0〜3 語)。Searcher#search_pattern と同じ分岐
      def search(words, class_only: false)
        if class_only
          raise InvalidKey, '--class option requires only 1 argument' unless words.size == 1
          return narrow(@classes, words[0] || raise, &:full_name)
        end
        case words.size
        when 0
          @classes.dup
        when 1
          search_one(words[0] || raise)
        when 2
          search_method(words[0] || raise, nil, words[1] || raise)
        when 3
          c, t, m = words[0] || raise, words[1] || raise, words[2] || raise
          raise InvalidKey, "'$' cannot be used as method type" if t == '$'
          raise InvalidKey, "unknown method type: #{t.inspect}" unless typemark?(t)
          search_method(c, t, m)
        else
          raise InvalidKey, "too many arguments (#{words.size} for 3)"
        end
      end

      private

      # Searcher#find_class_or_method と同じ優先順位。ライブラリと C の関数は
      # refe のローカル検索には無い追加の fallback
      def search_one(pat)
        case pat
        when /\A\$/   # 特殊変数
          narrow(@methods.select {|e| e.typechar == 'v' }, pat, &:name)
        when /[\#,]\.|\.[\#,]|[\#\.\,]/   # メソッド指定
          c, t, m = parse_method_spec_pattern(pat)
          search_method(c, t, m)
        when /::/   # クラス名か定数名
          found = narrow(@classes, pat, &:full_name)
          return found unless found.empty?
          names = pat.split('::')
          name = names.pop || raise
          search_method(names.join('::'), '::', name)
        when /\A[A-Z]/   # クラス名が優先
          found = narrow(@classes, pat, &:full_name)
          found = search_method(nil, nil, pat) if found.empty?
          found
        else
          found = search_method(nil, nil, pat)
          found = narrow(@classes, pat, &:full_name) if found.empty?
          found = narrow(@libraries, pat, &:full_name) if found.empty?
          found = narrow(@functions, pat, &:full_name) if found.empty?
          found
        end
      end

      def search_method(c, t, m)
        entries = @methods
        if c
          klasses = narrow(@classes, c, &:full_name).map(&:full_name)
          return [] if klasses.empty?
          entries = entries.select {|e| (k = e.klass) && klasses.include?(k) }
        end
        if t
          typechar = typemark2char(_ = t)
          entries = entries.select {|e| e.typechar == typechar }
        end
        narrow(entries, m, &:name)
      end

      # Completion#expand と同じ絞り込み: 大小無視の前方一致 → 大小無視の
      # 完全一致 → 完全一致。絞れなければ手前の結果を返す
      def narrow(xs, pattern)
        re1 = /\A#{Regexp.quote(pattern)}/i
        result1 = xs.select {|x| yield(x).match?(re1) }
        return result1 if result1.size <= 1
        re2 = /\A#{Regexp.quote(pattern)}\z/i
        result2 = result1.select {|x| yield(x).match?(re2) }
        return result1 if result2.empty?
        return result2 if result2.size == 1
        result3 = result2.select {|x| yield(x) == pattern }
        result3.empty? ? result2 : result3
      end
    end

    # URL ごとのファイルキャッシュ(dir/<ホスト>/<パス>)。mtime は最後に
    # 確認した時刻。max_age 以内ならそのまま使い、古ければ If-Modified-Since
    # で確認する(304 なら touch)。取得できなければ古いものを stale として返す
    class Cache
      MAX_AGE = 24 * 60 * 60

      # 取得結果。stale は接続できずに古いキャッシュを返したとき true
      class Hit
        attr_reader :body, :path, :stale

        def initialize(body:, path:, stale:)
          @body = body
          @path = path
          @stale = stale
        end
      end

      def initialize(dir:, fetcher:, max_age: MAX_AGE, clock: -> { Time.now })
        @dir = dir
        @fetcher = fetcher
        @max_age = max_age
        @clock = clock
      end

      # 本文を Hit で返す。404 なら nil。キャッシュが無くて取得にも失敗したら
      # 例外(Remote::NETWORK_ERRORS のどれか)
      def fetch(uri)
        path = path_for(uri)
        now = @clock.call
        cached = File.file?(path)
        if cached
          mtime = File.mtime(path)
          return Hit.new(body: read(path), path: path, stale: false) if mtime > now - @max_age
          headers = { 'If-Modified-Since' => mtime.httpdate }
        else
          headers = {} #: Hash[String, String]
        end
        begin
          status, body = @fetcher.call(uri, headers)
        rescue *NETWORK_ERRORS
          raise unless cached
          return Hit.new(body: read(path), path: path, stale: true)
        end
        case status
        when 200
          text = to_utf8(body)
          write(path, text, now)
          Hit.new(body: text, path: path, stale: false)
        when 304
          raise HTTPError, "304 without a cached copy: #{uri}" unless cached
          File.utime(now, now, path)
          Hit.new(body: read(path), path: path, stale: false)
        when 404
          File.delete(path) if cached
          nil
        else
          return Hit.new(body: read(path), path: path, stale: true) if cached
          raise HTTPError, "HTTP #{status}: #{uri}"
        end
      end

      private

      def path_for(uri)
        File.join(@dir, uri.host || raise, uri.path || raise)
      end

      def read(path)
        File.read(path, encoding: Encoding::UTF_8)
      end

      def write(path, text, now)
        FileUtils.mkdir_p(File.dirname(path))
        tmp = "#{path}.tmp"
        File.binwrite(tmp, text)
        File.rename(tmp, path)
        File.utime(now, now, path)
      end

      # 配信は text/markdown; charset=utf-8。Net::HTTP の本文は BINARY で返る
      def to_utf8(body)
        str = body.dup.force_encoding(Encoding::UTF_8)
        str.valid_encoding? ? str : str.scrub
      end
    end

    # Net::HTTP による既定の取得。同じホストへの接続は使い回し、close で閉じる。
    # gzip は Net::HTTP が自動で展開する(search_data.js は約 3MB・gzip 420KB)
    class HttpFetcher
      HEADERS = {
        'User-Agent' => "bitclust/#{BitClust::VERSION}",
        'Accept' => 'text/markdown, text/javascript, */*',
      }.freeze
      MAX_REDIRECTS = 2

      def initialize(open_timeout: 5, read_timeout: 30)
        @open_timeout = open_timeout
        @read_timeout = read_timeout
        @sessions = {}
      end

      def call(uri, headers = {})
        redirects = 0
        loop do
          res = session(uri).get(uri.path || raise, HEADERS.merge(headers))
          location = res['location']
          if res.is_a?(Net::HTTPRedirection) && location && redirects < MAX_REDIRECTS
            redirects += 1
            uri = URI.join(uri, location)
          else
            return [res.code.to_i, res.body.to_s]
          end
        end
      end

      def close
        @sessions.each_value {|http| http.finish if http.started? }
        @sessions.clear
      end

      private

      def session(uri)
        @sessions[[uri.host, uri.port]] ||=
          Net::HTTP.start(uri.host || raise, uri.port,
                          use_ssl: uri.scheme == 'https',
                          open_timeout: @open_timeout,
                          read_timeout: @read_timeout)
      end
    end
  end
end

# frozen_string_literal: true
#
# bitclust/link_checker.rb
#
# DB 全体を走査して [[c:]]/[[m:]]/[[lib:]]/[[d:]]/[[f:]] 参照の
# リンク切れを検出する。bitclust の参照リンクは描画時に存在検証されない
# (URL を文字列変換で組むだけ)ため、壊れた参照は静かにリンク切れになる。
#
# 参照の抽出は正規表現の自前スキャンではなく、実際のコンパイル経路
# (RDCompiler#bracket_link に仕込んだフック @option[:link_checker])で
# 行う。これにより「描画時に本当にリンクになるものだけ」が対象になり、
# コードスパン・コードフェンス内の参照風テキストは自然に除外される。

require 'bitclust/compat'
require 'bitclust/nameutils'
require 'bitclust/methodid'
require 'bitclust/exception'

module BitClust

  class LinkChecker

    Finding = Struct.new(:location, :ref, :message)

    # bracket_link が扱う型のうち、DB 外を指すので検証対象外のもの
    EXTERNAL_TYPES = %w[url man rfc RFC ruby-list ruby-dev ruby-ext
                        ruby-talk ruby-core feature bug misc].freeze

    def initialize(db, function_database: nil)
      @db = db
      @fdb = function_database
      @findings = [] #: Array[Finding]
      @current_location = nil #: String?
      @skipped_function_refs = 0
    end

    attr_reader :findings
    attr_reader :skipped_function_refs
    attr_accessor :current_location

    def broken_count
      @findings.size
    end

    # DB 中の全ソース(ライブラリ・クラス・メソッド・doc ページ)を
    # コンパイルして findings を収集する
    def check_all
      @db.libraries.sort_by(&:id).each do |lib|
        check_source(lib.source_location || "library #{lib.name}") {|c| c.compile(lib.source.to_s) }
      end
      @db.classes.sort_by(&:id).each do |klass|
        check_source(klass.source_location || "class #{klass.name}") {|c| c.compile(klass.source.to_s) }
        klass.entries.sort_by(&:id).each do |m|
          check_source(m.source_location || "#{klass.name} #{m.name}") {|c| c.compile_method(m) }
        end
      end
      @db.docs.sort_by(&:id).each do |doc|
        check_source(doc.source_location || "doc #{doc.name}") {|c| c.compile(doc.source.to_s) }
      end
      @findings
    end

    # RDCompiler#bracket_link から呼ばれるフック。描画には影響しない
    def note_ref(type, arg)
      case type
      when 'c'   then check_class(arg)
      when 'm'   then check_method(arg)
      when 'lib' then check_library(arg)
      when 'd'   then check_doc(arg)
      when 'f'   then check_function(arg)
      when 'ref' then check_ref(arg)
      else
        unless EXTERNAL_TYPES.include?(type)
          # 未知の型は bracket_link がリテラル [[...]] のまま出力する。
          # ほぼ確実に型名の書き間違いなので報告する
          record(type, arg, 'unknown link type')
        end
      end
      nil
    end

    private

    def check_source(location)
      # Location#to_s は行番号不明のとき "path:" になるので末尾の : を落とす
      @current_location = location.to_s.sub(/:\z/, '')
      compiler = new_compiler
      begin
        yield compiler
      rescue => err
        # コンパイル自体の失敗はリンク切れとは別問題(構文エラー等)。
        # チェックを止めず、報告だけして続行する
        record('compile', location.to_s, "compile failed: #{err.class}: #{err.message}")
      end
    ensure
      @current_location = nil
    end

    def new_compiler
      mapper_conf = Hash.new {|_h, _k| '' } #: untyped
      urlmapper = URLMapper.new(mapper_conf)
      opt = { :database => @db, :link_checker => self } #: RDCompiler::option
      if @db.properties['source_format'] == 'markdown'
        require 'bitclust/mdcompiler'
        gfm_opt = opt.merge(:gfm => true) #: RDCompiler::option
        MDCompiler.new(urlmapper, 1, gfm_opt)
      else
        require 'bitclust/rdcompiler'
        RDCompiler.new(urlmapper, 1, opt)
      end
    end

    def check_class(name)
      @db.fetch_class(name)
    rescue NotFoundError, InvalidKey
      record('c', name, 'class not found')
    end

    def check_method(spec_str)
      # rdcompiler の complete_spec と同じ補完($~ 等は Kernel の特殊変数)
      str = spec_str.start_with?('$') ? "Kernel#{spec_str}" : spec_str
      begin
        spec = MethodSpec.parse(str)
      rescue => _err
        record('m', spec_str, 'malformed method spec')
        return
      end
      # fetch_methods は不在時に空配列(truthy)を返してしまい raise しない
      # ため、単数形の fetch_method(不在で MethodNotFound)を使う
      @db.fetch_method(spec)
    rescue NotFoundError, InvalidKey
      record('m', spec_str, 'method not found')
    end

    def check_library(name)
      return if name == '/' || name == '_index'
      @db.fetch_library(name)
    rescue NotFoundError, InvalidKey
      record('lib', name, 'library not found')
    end

    def check_doc(name)
      @db.fetch_doc(name)
    rescue NotFoundError, InvalidKey
      record('d', name, 'doc not found')
    end

    def check_function(name)
      return if name == '/' || name == '_index' || name.empty?
      fdb = @fdb
      unless fdb
        @skipped_function_refs += 1
        return
      end
      fdb.fetch_function(name)
    rescue NotFoundError, InvalidKey
      record('f', name, 'function not found')
    end

    # [[ref:type:name#frag]] 形式のみ検証する(参照先本体の存在チェック)。
    # エントリローカルの [[ref:frag]] 形式は対象外(entry 文脈が必要で、
    # アンカー未定義でも描画は劣化表示に留まるため)
    def check_ref(arg)
      if /\A(\w+):(.*)\#[-\w]+\z/ =~ arg
        type, name = $1, $2
        case type
        when 'c'   then check_class(name || raise)
        when 'm'   then check_method(name || raise)
        when 'lib' then check_library(name || raise)
        when 'd'   then check_doc(name || raise)
        end
      end
    end

    def record(type, arg, message)
      @findings.push Finding.new(@current_location, "#{type}:#{arg}", message)
    end
  end
end

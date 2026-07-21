# frozen_string_literal: true
#
# bitclust/rrdparser.rb
#
# Copyright (c) 2006-2007 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

require 'bitclust/compat'
require 'bitclust/preprocessor'
require 'bitclust/methodid'
require 'bitclust/methoddatabase'
require 'bitclust/methodsignature'
require 'bitclust/lineinput'
require 'bitclust/parseutils'
require 'bitclust/nameutils'
require 'bitclust/exception'

module BitClust

  # Parser for Ruby API reference file (refm/api/src/*)
  class RRDParser

    include NameUtils
    include ParseUtils

    def RRDParser.parse_stdlib_file(path, params = {"version" => "1.9.0"})
      parser = new(MethodDatabase.dummy(params))
      parser.parse_file(path, libname(path), params)
    end

    def RRDParser.parse(s, lib, params = {"version" => "1.9.0"})
      parser = new(MethodDatabase.dummy(params))
      if s.respond_to?(:to_io)
        # @type var s: File
        io = s.to_io
      elsif s.respond_to?(:to_str)
        # @type var s: String
        s1 = s.to_str
        require 'stringio'
        io = StringIO.new(s1)
      else
        io = s
      end
      # @type var io: File | StringIO
      l = parser.parse(io, lib, params)
      return l, parser.db
    end

    def RRDParser.split_doc(source)
      if m = /^=(\[a:.*?\])?( +(.*)|([^=].*))\r?\n/.match(source)
        title = $3 || $4 || raise
        s = m.post_match
        return title, s
      end
      return ["", source]
    end

    def RRDParser.libname(path)
      case path
      when %r<(\A|/)_builtin/>
        '_builtin'
      else
        path.sub(%r<\A(.*/)?src/>, '').sub(/\.rd(\.off)?\z/, '')
      end
    end
    private_class_method :libname

    def initialize(db)
      @db = db
    end
    attr_reader :db

    def parse_file(path, libname, params = {})
      fopen(path, 'r:UTF-8') {|f|
        return parse(f, libname, params).tap { |lib| lib.source_location = Location.new(path, 1) }
      }
    end

    def parse(f, libname, params = {})
      @context = Context.new(@db, libname)
      f = LineInput.new(Preprocessor.wrap(f, params))
      do_parse f
      @context.library
    end

    private

    def do_parse(f)
      f.skip_blank_lines
      @context.categorize f.gets_if(/\Acategory\s(.*)/, 1)
      f.skip_blank_lines
      f.while_match(/\Arequire\s/) do |line|
        @context.require line.split[1]
      end
      f.skip_blank_lines
      f.while_match(/\Asublibrary\s/) do |line|
        @context.sublibrary line.split[1]
      end
      f.skip_blank_lines
      @context.library.source = f.break(/\A==?[^=]|\A---/).join('').rstrip
      read_classes f
      if line = f.gets   # error
        case line
        when /\A==[^=]/
          parse_error "met level-2 header in library document; maybe you forgot level-1 header", line
        when /\A---/
          parse_error "met bare method entry in library document; maybe you forgot reopen/redefine level-1 header", line
        else
          parse_error "unexpected line in library document", line
        end
      end
    end

    def read_classes(f)
      f.while_match(/\A=[^=]/) do |line|
        type, name, superclass = *parse_level1_header(line)
        case type
        when 'class'
          @context.define_class name, (superclass || 'Object'), location: line.location
          read_class_body f
        when 'module'
          parse_error "superclass given for module", line  if superclass
          @context.define_module name, location: line.location
          read_class_body f
        when 'object'
          @context.define_object name, superclass, location: line.location
          read_object_body f
        when 'reopen'
          @context.reopen_class name
          read_reopen_body f
        when 'redefine'
          @context.redefine_class name
          read_reopen_body f
        else
          parse_error "wrong level-1 header", line
        end
      end
    end

    def parse_level1_header(line)
      m = /\A(\S+)\s*([^\s<]+)(?:\s*<\s*(\S+))?\z/.match(line.sub(/\A=/, '').strip)
      unless m
        parse_error "level-1 header syntax error", line
      end
      return (m[1] || raise), isconst((m[2]), line), isconst((m[3]), line)
    end

    def isconst(name, line)
      return nil unless name
      unless /\A#{CLASS_PATH_RE}\z/o =~ name
        raise ParseError, "#{line.location}: not a constant: #{name.inspect}"
      end
      name
    end

    def read_class_body(f)
      f.skip_blank_lines
      read_aliases f
      f.skip_blank_lines
      read_extends f
      read_includes f
      f.skip_blank_lines
      @context.klass&.source = f.break(/\A==?[^=]|\A---/).join('').rstrip
      read_level2_blocks f
    end

    def read_reopen_body(f)
      f.skip_blank_lines
      read_extends f, true
      read_includes f, true
      f.skip_blank_lines
      read_level2_blocks f
    end

    def read_object_body(f)
      f.skip_blank_lines
      read_aliases f
      f.skip_blank_lines
      read_extends f
      f.skip_blank_lines
      @context.klass&.source = f.break(/\A==?[^=]|\A---/).join('').rstrip
      @context.visibility = :public
      @context.type = :singleton_method
      read_level2_blocks f
    end

    def read_aliases(f)
      f.while_match(/\Aalias\s/) do |line|
        @context.alias line.split[1]
      end
    end

    def read_includes(f, reopen = false)
      f.while_match(/\Ainclude\s/) do |line|
        if reopen
          @context.dynamic_include(line.split[1])
        else
          @context.include(line.split[1])
        end
      end
    end

    def read_extends(f, reopen = false)
      f.while_match(/\Aextend\s/) do |line|
        if reopen
          @context.dynamic_extend(line.split[1])
        else
          @context.extend(line.split[1])
        end
      end
    end

    def tty_warn(msg)
      $stderr.puts msg if $stderr.tty?
    end

    def read_level2_blocks(f)
      read_entries f
      f.skip_blank_lines
      f.while_match(/\A==[^=]/) do |line|
        case line.sub(/\A==/, '').strip
        when /\A((?:public|private|protected)\s+)?(?:(class|singleton|instance)\s+)?methods?\z/i
          # @type var visibility: :public | :private | :protected
          visibility = ($1 || 'public').downcase.strip.intern
          @context.visibility = visibility
          t = ($2 || 'instance').downcase.sub(/class/, 'singleton')
          @context.type = _ = "#{t}_method".intern
        when /\AModule\s+Functions?\z/i
          @context.module_function
        when /\AConstants?\z/i
          @context.constant
        when /\ASpecial\s+Variables?\z/i
          @context.special_variable
        else
          parse_error "unknown level-2 header", line
        end
        read_entries f
      end
    end

    def read_entries(f)
      concat_aliases(read_chunks(f)).each do |chunk|
        @context.define_method chunk
      end
    end

    def concat_aliases(chunks)
      return [] if chunks.empty?
      result = [chunks.shift || raise]
      chunks.each do |chunk|
        if result.last&.alias?(chunk)
          result.last&.unify chunk
        else
          result.push chunk
        end
      end
      result
    end

    def read_chunks(f)
      f.skip_blank_lines
      result = [] #: Array[Chunk]
      f.while_match(/\A---/) do |line|
        f.ungets line
        result.push read_chunk(f)
      end
      result
    end

    # シグネチャ行に続くメソッド属性行({: ...}。直前のシグネチャ行に束縛)
    METHOD_ATTRIBUTE_LINE_RE = /\A\{:.*\}[ \t]*$/

    def read_chunk(f)
      # シグネチャ行の直後には {: ...} 属性行を置ける。属性行を挟んでも
      # ひとつのチャンク(別名グループ)として読む
      header = [] #: Array[String]
      sig_lines = [] #: Array[String]
      while f.next?
        if /\A---/ =~ f.peek
          line = f.gets or raise
          header.push line
          sig_lines.push line
        elsif !sig_lines.empty? && METHOD_ATTRIBUTE_LINE_RE =~ f.peek
          header.push(f.gets || raise)
        else
          break
        end
      end
      body = f.break(/\A(?:---|={1,2}[^=])/)
      src = (header + body).join('')
      src.location = sig_lines[0].location
      sigs = sig_lines.map {|line| method_signature(line) }
      mainsig = check_chunk_signatures(sigs, sig_lines[0])
      names = sigs.map {|s| s.name }.compact.uniq.sort
      Chunk.new(mainsig, names, src)
    end

    def check_chunk_signatures(sigs, line)
      cxt = @context.signature
      if cxt and cxt.fully_qualified?
        if bad = sigs.detect {|sig| not cxt.compatible?(sig) }
          parse_error "signature crash: `#{cxt}' given by level-1/2 header but method entry has a signature `#{bad}'; remove level-1/2 header or modify method entry", line
        end
        cxt
      else
        sig = sigs[0]
        unless sig.fully_qualified?
          if not cxt
            parse_error "missing class and type; give full signature for method entry", line
          elsif not cxt.type
            parse_error "missing type: write level-2 header", line
          elsif not cxt.klass
            raise "must not happen: type given but class not exist: context=#{cxt}, entry=#{sig}"
          else
            raise "must not happen: context=#{cxt}, entry=#{sig}"
          end
        end
        if cxt
          unless sig.compatible?(cxt)
            parse_error "signature crash: #{cxt} given by level-1/2 but method entry has a signature #{sig}; remove level-1/2 header or modify method entry", line
          end
        end
        unless sigs.all? {|s| sig.same_type?(s) }
          parse_error "alias entries have different class/type", line
        end
        sig
      end
    end

    SIGNATURE = /\A---\s*(?:(#{CLASS_PATH_RE})(#{TYPEMARK_RE}))?(#{METHOD_NAME_RE})/
    GVAR = /\A---\s*(#{GVAR_RE})/

    def method_signature(line)
      case
      when m = SIGNATURE.match(line)
        klass, typemark_, name = m.captures
        # @type var typemark: NameUtils::typemark
        typemark = _ = typemark_
        Signature.new(klass, typemark, name)
      when m = GVAR.match(line)
        Signature.new(nil, '$', (m[1] || raise)[1..-1])
      else
        parse_error "wrong method signature", line
      end
    end

    class Context
      include NameUtils

      def initialize(db, libname)
        @db = db
        #@library = @db.open_library(libname)
        @library = @db.open_library(libname, true)   # FIXME: always reopen
        @klass = nil
        @type = nil
        @visibility = nil
      end

      attr_reader :library
      attr_reader :klass
      attr_accessor :type
      attr_accessor :visibility

      def categorize(category)
        @library.category = category
      end

      def require(libname)
        @library.require @db.get_library(libname)
      end

      def sublibrary(libname)
        @library.sublibrary @db.get_library(libname)
      end

      def define_class(name, supername, location: nil)
        if @db.properties['version'] >= "1.9.0"
          top = 'BasicObject'
        else
          top = 'Object'
        end
        superclass = (name == top ? nil : @db.get_class(supername))
        register_class :class, name, superclass, location: location
      end

      def define_module(name, location: nil)
        register_class :module, name, nil, location: location
      end

      def define_object(name, singleton_object_class, location: nil)
        singleton_object_class = @db.get_class(singleton_object_class) if singleton_object_class
        # steep:ignore:start
        register_class :object, name, singleton_object_class, location: location
        # steep:ignore:end
      end

      def register_class(type, name, superclass, location: nil)
        name or raise
        @klass = @db.open_class(name) {|c|
          c.type = type
          c.superclass = superclass
          c.library = @library
          c.source_location = location
          @library.add_class c
        }
        @kind = :defined
        clear_scope
      end
      private :register_class

      def clear_scope
        @type = nil
        @visibility = nil
      end
      private :clear_scope

      def reopen_class(name)
        @kind = :added
        @klass = name ? @db.get_class(name) : nil
        clear_scope
      end

      def redefine_class(name)
        @kind = :redefined
        @klass = name ? @db.get_class(name) : nil
        clear_scope
      end

      def include(name)
        @klass&.include @db.get_class(name)
      end

      def extend(name)
        @klass&.extend @db.get_class(name)
      end

      def dynamic_include(name)
        @klass&.dynamic_include(@db.get_class(name), @library)
      end

      def dynamic_extend(name)
        @klass&.dynamic_extend(@db.get_class(name), @library)
      end

      # Add a alias +name+ to the alias list.
      def alias(name)
        klass = @klass || raise
        @db.open_class(name) do |c|
          c.type = klass.type
          c.library = @library
          c.aliasof = klass
          c.source = "Alias of [[c:#{klass.name}]]\n"
          @library.add_class c
          klass.alias c
        end
      end

      def module_function
        @type = :module_function
      end

      def constant
        @type = :constant
      end

      def special_variable
        unless @klass and @klass&.name == 'Kernel'
          raise "must not happen: type=special_variable but class!=Kernel"
        end
        @type = :special_variable
      end

      def signature
        return nil unless @klass
        Signature.new(@klass&.name, @type ? typename2mark(@type || raise) : nil, nil)
      end

      def define_method(chunk)
        id = method_id(chunk)
        attrs = method_attributes(chunk)
        @db.open_method(id) {|m|
          m.names           = chunk.names.sort
          m.kind            = if attrs.flags.include?('undef')
                                :undefined
                              elsif attrs.flags.include?('nomethod')
                                :nomethod
                              else
                                @kind
                              end
          # steep:ignore:start
          m.visibility      = @visibility || :public
          # steep:ignore:end
          m.source          = chunk.source
          m.source_location = chunk.source.location
          attrs.since_until.each do |name, kv|
            m.fill_since(name, kv['since'] || raise) if kv['since']
            m.fill_until(name, kv['until'] || raise) if kv['until']
          end
          case @kind
          when :added, :redefined
            @library.add_method m
          end
        }
      end

      # 現在サポートするメソッド属性({: ...} 属性行のトークン)。
      # - nomethod/undef: 裸語。kind はエントリ単位でしか持てないので、
      #   別名(複数シグネチャ)のエントリでは全シグネチャに同じ属性が
      #   付いていることを要求する
      # - since="X"/until="X"(bitclust#132 P4): シグネチャ単位で束縛され、
      #   そのシグネチャの名前だけに適用される。nomethod/undef と違い、
      #   別名ごとに異なる値を持てる(全シグネチャ一致は要求しない)のが
      #   本来の用途。X は "3.2" のように数字とドットのみ。
      #   空値(since="")は「明示的に不明」= バッジ非表示の指定で、メソッド
      #   自体は昔からあるのにドキュメント追加が遅れ、バージョンラダーからの
      #   自動算出が誤った版を出す場合の抑止に使う(空文字が記録されるため
      #   算出値で上書きされず、表示側も空はバッジを出さない)
      METHOD_ATTRIBUTES = %w[nomethod undef]
      KV_METHOD_ATTRIBUTES = %w[since until]
      KV_METHOD_ATTRIBUTE_VALUE_RE = /\A(?:\d+(?:\.\d+)*)?\z/

      # md の `### def name ...`/`### module_function def name ...`/
      # `### const name`/`### gvar $name` シグネチャ行を rd 形式
      # (`--- name ...`)へ正規化するための接頭辞(MDParser::SIG_RE と
      # 同じパターン)。属性の紐付け先となるメソッド名を
      # MethodSignature.parse で取り出すために使う
      MD_METHOD_SIG_PREFIX_RE = /\A### (?:module_function def |def |const |gvar )/

      # method_attributes の返り値。
      # - flags: 裸語トークン(nomethod/undef)の集合。エントリ単位の属性
      #   なので全シグネチャで同一であることを method_attributes が保証済み
      # - since_until: シグネチャ単位で束縛された since="X"/until="X" を
      #   { メソッド名 => { "since" => "X", "until" => "X" } } の形で保持する
      MethodAttributes = Struct.new(:flags, :since_until)

      # kramdown Block IAL 風の {: ...} 属性行からメタデータを集める。
      # 属性行は「直前のシグネチャ行のみ」に束縛される(kramdown と同じ解釈)。
      # 裸語トークン(nomethod/undef)は kind がエントリ単位でしか持てないため
      # 全シグネチャで同じであることを要求するが、since=/until= はシグネチャ
      # 単位でそのままの名前に適用するため、この一致要求からは除外する。
      # 本文に入ったら探索を打ち切る(コード例中の {: ...} を誤検出しないため)
      def method_attributes(chunk)
        per_sig = [] #: Array[Array[String]]
        since_until = {} #: Hash[String, Hash[String, String]]
        current_name = nil #: String?
        current_keys = nil #: Hash[String, bool]?
        chunk.source.each_line do |line_|
          line = line_.chomp
          case line
          when /\A---\s/, /\A\#\#\#\s/
            per_sig.push []
            current_name = method_attribute_target_name(line)
            current_keys = {}
          when /\A\{:(.*)\}[ \t]*\z/
            break if per_sig.empty?
            ($1 || raise).strip.split(/\s+/).each do |token|
              if METHOD_ATTRIBUTES.include?(token)
                per_sig.last&.push token
              else
                key, value = parse_kv_method_attribute(token, chunk)
                keys = current_keys or raise
                if keys.key?(key)
                  raise ParseError,
                        "#{chunk.source.location}: duplicate method attribute #{key.inspect} on the same signature"
                end
                keys[key] = true
                name = current_name or
                  raise ParseError,
                        "#{chunk.source.location}: cannot determine the signature name to bind method attribute #{token.inspect} to"
                (since_until[name] ||= {})[key] = value
              end
            end
          else
            break
          end
        end
        return MethodAttributes.new([], {}) if per_sig.empty?
        sets = per_sig.map {|a| a.uniq.sort }
        unless sets.uniq.size == 1
          raise ParseError,
                "#{chunk.source.location}: method attributes must be the same on every signature of an entry: #{sets.inspect}"
        end
        # 紐付け先の名前がエントリの names と食い違ったら黙って捨てずに
        # エラーにする(名前導出の規約ずれを CI で検出するための安全網)
        since_until.each_key do |name|
          unless chunk.names.include?(name)
            raise ParseError,
                  "#{chunk.source.location}: since/until attribute bound to unknown signature name #{name.inspect} (entry names: #{chunk.names.join(', ')})"
          end
        end
        MethodAttributes.new(sets.first || raise, since_until)
      end

      # since="X"/until="X" 形式のトークンを解析して [key, value] を返す。
      # 受理する形式以外(キーが不明・値が非引用・値が数字とドット以外を
      # 含む等)はすべて ParseError にする
      def parse_kv_method_attribute(token, chunk)
        m = /\A(\w+)=(.*)\z/.match(token)
        if m
          key = m[1] || raise
          raw_value = m[2] || raise
          quoted = /\A"(.*)"\z/.match(raw_value)
          if quoted && KV_METHOD_ATTRIBUTES.include?(key) && KV_METHOD_ATTRIBUTE_VALUE_RE.match?(quoted[1] || raise)
            return [key, (quoted[1] || raise)]
          end
        end
        raise ParseError,
              "#{chunk.source.location}: invalid method attribute #{token.inspect} " \
              "(supported: #{METHOD_ATTRIBUTES.join(', ')}, " \
              "#{KV_METHOD_ATTRIBUTES.map {|k| %Q(#{k}="X") }.join('/')} where X is digits and dots, e.g. since=\"3.2\", " \
              "or empty for explicitly-unknown, e.g. since=\"\")"
      end
      private :parse_kv_method_attribute

      # シグネチャ行(rd の `--- ...` / md の `### def ...` 等)から、
      # 属性の紐付け先となるメソッド名を取り出す。
      # 特殊変数のシグネチャ名は "$SAFE" のように $ 付きだが、エントリの
      # names は先頭の $ を除いた形("SAFE"。"$$" なら "$")で格納される
      # (method_signature の Signature.new(nil, '$', name[1..-1]) と同じ規約)
      # ため、since_by_name のキーも names に合わせて $ を1つ剥がす
      def method_attribute_target_name(line)
        normalized = line.sub(MD_METHOD_SIG_PREFIX_RE, '--- ')
        MethodSignature.parse(normalized).name.sub(/\A\$/, '')
      rescue ParseError
        nil
      end
      private :method_attribute_target_name

      def method_id(chunk)
        id = MethodID.new
        id.library = @library
        id.klass   = chunk.signature.klass ? @db.get_class(chunk.signature.klass) : (@klass || raise)
        id.type    = chunk.signature.typename || @type
        id.name    = chunk.names.sort.first
        id
      end
    end

    class Chunk
      def initialize(signature, names, source)
        @signature = signature
        @names = names
        @source = source
      end

      attr_reader :signature
      attr_reader :names
      attr_reader :source

      def inspect
        "\#<Chunk #{@signature.klass}#{@signature.type}#{@names.join(',')} #{@source.location}>"
      end

      def alias?(other)
        @signature.compatible?(other.signature) and
            not (@names & other.names).empty?
      end

      def unify(other)
        @names |= other.names
        @source << other.source
      end
    end

    class Signature
      include NameUtils

      def initialize(c, t, m)
        @klass = c   # String
        @type = t
        @name = m
      end

      attr_reader :klass
      attr_reader :type
      attr_reader :name

      def inspect
        "\#<signature #{to_s()}>"
      end

      def to_s
        "#{@klass || '_'}#{@type || ' _ '}#{@name}"
      end

      def typename
        typemark2name(_ = @type)
      end

      def same_type?(other)
        @klass == other.klass and @type == other.type
      end

      def compatible?(other)
        (not @klass or not other.klass or @klass == other.klass) and
        (not @type  or not other.type  or @type  == other.type)
      end

      def fully_qualified?
        (@klass and @type) ? true : false
      end
    end

  end

end

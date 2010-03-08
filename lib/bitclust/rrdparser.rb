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
require 'bitclust/lineinput'
require 'bitclust/parseutils'
require 'bitclust/nameutils'
require 'bitclust/exception'

module BitClust

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
        io = s.to_io
      elsif s.respond_to?(:to_str)
        s1 = s.to_str
        require 'stringio'
        io = StringIO.new(s1)
      else
        io = s
      end
      l = parser.parse(io, lib, params)
      return l, parser.db
    end

    def RRDParser.split_doc(source)
      if m = /^=(\[a:.*?\])?( +(.*)|([^=].*))\r?\n/.match(source)
        title = $3 || $4
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
      fopen(path, 'r:EUC-JP') {|f|
        return parse(f, libname, params)
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
          @context.define_class name, (superclass || 'Object')
          read_class_body f
        when 'module'
          parse_error "superclass given for module", line  if superclass
          @context.define_module name
          read_class_body f
        when 'object'
          if superclass
            # FIXME
tty_warn "#{line.location}: singleton object class not implemented yet"
          end
          @context.define_object name
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
      return m[1], isconst(m[2], line), isconst(m[3], line)
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
      @context.klass.source = f.break(/\A==?[^=]|\A---/).join('').rstrip
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
      @context.klass.source = f.break(/\A=|\A---/).join('').rstrip
      @context.visibility = :public
      @context.type = :singleton_method
      read_entries f
    end

    def read_aliases(f)
      f.while_match(/\Aalias\s/) do |line|
#tty_warn "#{line.location}: class alias is not implemented yet"
        # FIXME
      end
    end

    def read_includes(f, reopen = false)
      f.while_match(/\Ainclude\s/) do |line|
tty_warn "#{line.location}: dynamic include is not implemented yet" if reopen
        @context.include line.split[1]          unless reopen # FIXME
      end
    end

    def read_extends(f, reopen = false)
      f.while_match(/\Aextend\s/) do |line|
tty_warn "#{line.location}: dynamic extend is not implemented yet" if reopen
        @context.extend line.split[1]           unless reopen # FIXME
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
          @context.visibility = ($1 || 'public').downcase.intern
          t = ($2 || 'instance').downcase.sub(/class/, 'singleton')
          @context.type = "#{t}_method".intern
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
      result = [chunks.shift]
      chunks.each do |chunk|
        if result.last.alias?(chunk)
          result.last.unify chunk
        else
          result.push chunk
        end
      end
      result
    end

    def read_chunks(f)
      f.skip_blank_lines
      result = []
      f.while_match(/\A---/) do |line|
        f.ungets line
        result.push read_chunk(f)
      end
      result
    end

    def read_chunk(f)
      header = f.span(/\A---/)
      body = f.break(/\A(?:---|={1,2}[^=])/)
      src = (header + body).join('')
      src.location = header[0].location
      sigs = header.map {|line| method_signature(line) }
      mainsig = check_chunk_signatures(sigs, header[0])
      names = sigs.map {|s| s.name }.uniq.sort
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
        Signature.new(*m.captures)
      when m = GVAR.match(line)
        Signature.new(nil, '$', m[1][1..-1])
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

      def require(libname)
        @library.require @db.get_library(libname)
      end

      def sublibrary(libname)
        @library.sublibrary @db.get_library(libname)
      end
      
      def define_class(name, supername)
        if @db.properties['version'] >= "1.9.0"
          top = 'BasicObject'
        else
          top = 'Object'
        end
        superclass = (name == top ? nil : @db.get_class(supername))
        register_class :class, name, superclass
      end

      def define_module(name)
        register_class :module, name, nil
      end

      def define_object(name)
        register_class :object, name, nil
      end

      def register_class(type, name, superclass)
        @klass = @db.open_class(name) {|c|
          c.type = type
          c.superclass = superclass
          c.library = @library
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
        @klass.include @db.get_class(name)
      end

      def extend(name)
        @klass.extend @db.get_class(name)
      end

      def module_function
        @type = :module_function
      end

      def constant
        @type = :constant
      end

      def special_variable
        unless @klass and @klass.name == 'Kernel'
          raise "must not happen: type=special_variable but class!=Kernel"
        end
        @type = :special_variable
      end

      def signature
        return nil unless @klass
        Signature.new(@klass.name, @type ? typename2mark(@type) : nil, nil)
      end

      def define_method(chunk)
        id = method_id(chunk)
        @db.open_method(id) {|m|
          m.names      = chunk.names.sort
          m.kind       = @kind
          m.visibility = @visibility || :public
          m.source     = chunk.source
          case @kind
          when :added, :redefined
            @library.add_method m
          end
        }
      end

      def method_id(chunk)
        id = MethodID.new
        id.library = @library
        id.klass   = chunk.signature.klass ? @db.get_class(chunk.signature.klass) : @klass
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
        typemark2name(@type)
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

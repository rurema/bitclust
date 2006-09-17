#
# bitclust/rrdparser.rb
#
# Copyright (c) 2006 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

require 'bitclust/lineinput'
require 'bitclust/nameutils'
require 'bitclust/exception'
require 'strscan'

class String   # reopen
  attr_accessor :location
end

module BitClust

  class LineStream
    def initialize(f)
      @f = f
    end

    def gets
      line = @f.gets
      return nil unless line
      line.location = Location.new(@f.path, @f.lineno)
      line
    end
  end


  class Location
    def initialize(file, line)
      @file = file
      @line = line
    end

    attr_reader :file
    attr_reader :line

    def to_s
      "#{@file}:#{@line}"
    end

    def inspect
      "\#<#{self.class} #{@file}:#{@line}>"
    end
  end


  module CompileUtils
    def compile_error(msg, line)
      raise CompileError, "#{line.location}: #{msg}: #{line.inspect}"
    end
  end


  class RRDParser

    include CompileUtils

    def RRDParser.parse_stdlib_file(path)
      parser = new(Database.dummy)
      parser.parse_file(path, libname(path), {"version" => "1.9.0"})
    end

    def RRDParser.libname(path)
      case path
      when %r<(\A|/)_builtin/>
        '_builtin'
      else
        path.sub(%r<\A(.*/)?src/>, '').sub(/\.rd(\.off)\z/, '')
      end
    end
    private_class_method :libname

    def initialize(db)
      @db = db
    end

    def parse_file(path, libname, params = {})
      File.open(path) {|f|
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
      f.while_match(/\Arequire /) do |line|
        @context.require line.split[1]
      end
      f.skip_blank_lines
      @context.library.source = f.break(/\A=[^=]/).join('').rstrip
      read_classes f
      unless f.eof?
        compile_error "syntax error", f.gets
      end
    end

    def read_classes(f)
      f.while_match(/\A=[^=]/) do |line|
        type, name, _, superclass, = *line.sub(/\A=/, '').split
        case type
        when 'class'
          @context.define_class name, (superclass || 'Object')
          read_class_body f
        when 'module'
          compile_error "superclass given for module", line  if superclass
          @context.define_module name
          read_class_body f
        when 'object'
          compile_error "superclass given for object", line  if superclass
          @context.define_object name
          f.skip_blank_lines
          f.while_match(/\Aextend\s/) do |line|
            @context.extend line.split[1]
          end
          f.skip_blank_lines
          @context.klass.source = f.break(/\A=|\A---/).join('').rstrip
          @context.visibility = :public
          @context.type = :singleton_method
          read_entries f
        when 'reopen'
          @context.reopen_class name
          read_class_body f
        when 'redefine'
          @context.redefine_class name
          read_class_body f
        else
          compile_error "wrong level-1 header", line
        end
      end
    end

    def read_class_body(f)
      f.skip_blank_lines
      f.while_match(/\Ainclude\s/) do |line|
        @context.include line.split[1]
      end
      f.skip_blank_lines
      @context.klass.source = f.break(/\A==?[^=]|\A---/).join('').rstrip
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
          compile_error "unknown level-2 header", line
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
      check_chunk_signatures sigs, header[0]
      names = sigs.map {|s| s.name }.uniq.sort
      Chunk.new((@context.signature || sigs.first), names, src)
    end

    def check_chunk_signatures(sigs, line)
      if cxt = @context.signature
        unless cxt.fully_qualified?
          compile_error "unqualified signature (#{cxt})", line
        end
        if sig = sigs.detect {|sig| not cxt.compatible?(sig) }
          compile_error "incompatible signature: #{cxt} <-> #{sig}", line
        end
      else
        unless sigs[0].fully_qualified?
          compile_error "unqualified signature (#{sigs[0]})", line
        end
        if sigs.all? {|s| sigs[0].same_type?(s) }
          compile_error "alias entries have multiple class/type", line
        end
      end
    end

    const = /[A-Z]\w*/
    cpath = /#{const}(?:::#{const})*/
    mid = /\w+[?!=]?|===|==|=~|<=|=>|<=>|\[\]=|\[\]|\*\*|>>|<<|\+@|\-@|[~+\-*\/%&|^<>`]/
    SIGNATURE = /\A---\s*(?:(#{cpath})([\.\#]|::))?(#{mid})/
    SVAR = /\A---\s*\$(\w+|-.|\S)/

    def method_signature(line)
      if m = SIGNATURE.match(line)
        Signature.new(m[1], m[2], m[3])
      elsif m = SVAR.match(line)
        Signature.new(nil, '$', m[1])
      else
        compile_error "failed to parse method signature", line
      end
    end

    class Context
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

      def define_class(name, supername)
        register_class :class, name, @db.get_class(supername)
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

      include NameUtils

      def signature
        return nil unless @klass
        Signature.new(@klass, @type ? typename2mark(@type) : nil, nil)
      end

      def define_method(chunk)
        spec = method_spec(chunk)
        @db.open_method(spec) {|m|
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

      def method_spec(chunk)
        spec = MethodSpec.new
        spec.library = @library
        spec.klass   = chunk.signature.klass || @klass
        spec.type    = chunk.signature.typename || @type
        spec.name    = chunk.names.sort.first
        spec
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
        "\#<Chunk #{@signature.klass.name}#{@signature.type}#{@names.join(',')} #{@source.location}>"
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
        @klass = c
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
        not not (@klass and @type)
      end
    end
  
  end


  class Preprocessor

    include CompileUtils
    include Enumerable

    def Preprocessor.process(path, params = {})
      File.open(path) {|f|
        return wrap(f, params).to_a
      }
    end

    def Preprocessor.wrap(f, params = {})
      new(params, LineStream.new(f))
    end

    def initialize(params, f)
      @params = params
      @f = f
      @buf = []
      @cond_stack = [true]
    end

    def gets
      @buf.shift || next_line(@f)
    end

    def each
      while line = gets()
        yield line
      end
    end

    private

    def next_line(f)
      last_if = nil
      while line = f.gets
        case line
        when /\A\#@\#/   # preprocessor comment
          ;
        when /\A\#@include\s*\((.*?)\)/
          file = $1.strip
          basedir = File.dirname(line.location.file)
          @buf.concat Preprocessor.process("#{basedir}/#{file}", @params)
        when /\A\#@if/
          last_if = line
          begin
            @cond_stack.push(@cond_stack.last && eval_cond(cond_expr(line)))
          rescue ScanError => err
            compile_error err.message, line
          end
        when /\A\#@else/
          compile_error "no matching #@if", line  if @cond_stack.size == 1
          b = @cond_stack.pop
          @cond_stack.push(!b && @cond_stack.last)
        when /\A\#@end\s*\z/
          compile_error "no matching #@if", line  if @cond_stack.size == 1
          @cond_stack.pop
        when /\A\#@/
          compile_error "unknown preprocessor directive", line
        else
          if @cond_stack.last
            @buf.push line
            break
          end
        end
      end
      if @buf.empty?
        unless @cond_stack.size == 1
          compile_error "unterminated \#@if", line
        end
      end
      @buf.shift
    end

    def cond_expr(line)
      line.slice(/\A\#@if\s*\((.*)\)\s*\z/, 1) or
          compile_error "syntax error: wrong #@if/#@elsif", line
    end

    def eval_cond(str)
      eval_expr(StringScanner.new(str)) ? true : false
    end

    def eval_expr(s)
      val = eval_primary(s)
      while op = read_op(s)
        val = val.__send__(op, eval_primary(s))
      end
      val
    end

    def read_op(s)
      s.skip(/\s+/)
      return nil if s.eos?
      s.scan(/>=|<=|==|<|>/) or
          scan_error "unknown op at #{s.rest.inspect}"
    end

    def eval_primary(s)
      s.skip(/\s+/)
      if t = s.scan(/\w+/)
        unless @params.key?(t)
          scan_error "unknown preproc variable #{t.inspect}"
        end
        @params[t]
      elsif t = s.scan(/".*?"/)
        eval(t)
      elsif t = s.scan(/'.*?'/)
        eval(t)
      elsif t = s.scan(/\d+/)
        t.to_i
      else
        scan_error "parse error at: #{s.inspect}"
      end
    end

    def scan_error(msg)
      raise ScanError, msg
    end

  end

end

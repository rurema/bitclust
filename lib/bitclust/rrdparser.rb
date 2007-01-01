#
# bitclust/rrdparser.rb
#
# Copyright (c) 2006 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

require 'bitclust/compat'
require 'bitclust/methodid'
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


  module ParseUtils
    def parse_error(msg, line)
      raise ParseError, "#{line.location}: #{msg}: #{line.inspect}"
    end
  end


  class RRDParser

    include NameUtils
    include ParseUtils

    def RRDParser.parse_stdlib_file(path)
      parser = new(Database.dummy)
      parser.parse_file(path, libname(path), {"version" => "1.9.0"})
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
        parse_error "unexpected line", f.gets
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
          parse_error "superclass given for module", line  if superclass
          @context.define_module name
          read_class_body f
        when 'object'
          parse_error "superclass given for object", line  if superclass
          @context.define_object name
          f.skip_blank_lines
          f.while_match(/\Aextend\s/) do |ex|
            @context.extend ex.split[1]
          end
          f.skip_blank_lines
          @context.klass.source = f.break(/\A=|\A---/).join('').rstrip
          @context.visibility = :public
          @context.type = :singleton_method
          read_entries f
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

    def read_reopen_body(f)
      f.skip_blank_lines
      read_level2_blocks f
    end

    def read_class_body(f)
      f.skip_blank_lines
      f.while_match(/\Ainclude\s/) do |line|
        @context.include line.split[1]
      end
      f.skip_blank_lines
      @context.klass.source = f.break(/\A==?[^=]|\A---/).join('').rstrip
      read_level2_blocks f
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
        if _sig = sigs.detect {|sig| not cxt.compatible?(sig) }
          parse_error "incompatible signature: #{cxt} <-> #{_sig}", line
        end
        cxt
      else
        unless sigs[0].fully_qualified?
          parse_error "unqualified signature (#{sigs[0]})", line
        end
        if cxt
          unless sigs[0].compatible?(cxt)
            parse_error "incompatible signature: #{cxt} <-> #{sigs[0]}", line
          end
        end
        unless sigs.all? {|s| sigs[0].same_type?(s) }
          parse_error "alias entries have multiple class/type", line
        end
        sigs.first
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

      def define_class(name, supername)
        superclass = (name == 'Object' ? nil : @db.get_class(supername))
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
        not not (@klass and @type)
      end
    end
  
  end


  class Preprocessor

    include ParseUtils
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
      @last_if = nil
      cond_init
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
      while line = f.gets
        case line
        when /\A\#@\#/   # preprocessor comment
          ;
        when /\A\#@todo/i
          ;
        when /\A\#@include\s*\((.*?)\)/
          begin
            file = $1.strip
            basedir = File.dirname(line.location.file)
            @buf.concat Preprocessor.process("#{basedir}/#{file}", @params)
          rescue Errno::ENOENT => err
            raise WrongInclude, "#{line.location}: \#@include'ed file not exist: #{file}"
          end
        when /\A\#@since\b/
          @last_if = line
          begin
            cond_push eval_cond(build_cond_by_value(line, 'version >='))
          rescue ScanError => err
            parse_error err.message, line
          end
        when /\A\#@if\b/
          @last_if = line
          begin
            cond_push eval_cond(line.sub(/\A\#@if/, '').strip)
          rescue ScanError => err
            parse_error err.message, line
          end
        when /\A\#@else\s*\z/
          parse_error "no matching #@if", line  if cond_toplevel?
          cond_invert
        when /\A\#@end\s*\z/
          parse_error "no matching #@if", line  if cond_toplevel?
          cond_pop
        when /\A\#@/
          parse_error "unknown preprocessor directive", line
        else
          if @cond_stack.last
            @buf.push line
            break
          end
        end
      end
      if @buf.empty?
        unless cond_toplevel?
          parse_error "unterminated \#@if", @last_if
        end
      end
      @buf.shift
    end

    def build_cond_by_value(line, left)
      case ver = line.sub(/\A\#@since/, '').strip
      when /\A[\d\.]+\z/
        %Q(#{left} "#{ver}")
      when /\A"[\d\.]+"\z/
        "#{left} #{ver}"
      else
        parse_error "wrong #@since line", line
      end
    end

    def cond_init
      @cond_stack = [true]
    end

    def cond_toplevel?
      @cond_stack.size == 1
    end

    def cond_push(bool)
      @cond_stack.push(@cond_stack.last && bool)
    end

    def cond_invert
      b = @cond_stack.pop
      @cond_stack.push(!b && @cond_stack.last)
    end

    def cond_pop
      @cond_stack.pop
    end

    def eval_cond(str)
      s = StringScanner.new(str)
      result = eval_expr(s) ? true : false
      unless s.eos?
        scan_error "parse error at: #{s.inspect}"
      end
      result
    end

    def eval_expr(s)
      paren_open = s.scan(/\s*\(/)
      val = eval_primary(s)
      while op = read_op(s)
        if op == '!='
          val = (val != eval_primary(s))
        else
          val = val.__send(op, eval_primary(s))
        end
      end
      if paren_open
        unless s.skip(/\s*\)/)
          scan_error "paren opened but not closed"
        end
      end
      val
    end

    def read_op(s)
      s.skip(/\s+/)
      s.scan(/>=|<=|==|<|>|!=/)
    end

    def eval_primary(s)
      s.skip(/\s+/)
      if t = s.scan(/\w+/)
        unless @params.key?(t)
          scan_error "database property `#{t}' not exist"
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

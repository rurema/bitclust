require 'bitclust/lineinput'
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


  module CompilerUtils
    def compile_error(msg, line)
      raise CompileError, "#{line.location}: #{msg}: #{line.inspect}"
    end
  end


  class RRDParser

    include CompilerUtils

    def initialize(db)
      @db = db
    end

    def parse_file(path, params = {})
      libname = File.basename(path, '.rd')
      File.open(path) {|f|
        preproc = Preprocessor.wrap(f, params)
        return parse(preproc, libname, path)
      }
    end

    def parse(input, libname, path)
      f = LineInput.new(input)
      f.skip_blank_lines
      reqs = f.span(/\Arequire /).map {|line| line.split[1] }
      f.skip_blank_lines
      src = f.break(/\A=[^=]/).join('').rstrip
      lib = LibraryDescription.new(libname, reqs, src)
      read_classes f, lib
      unless f.eof?
        compile_error "syntax error", f.gets
      end
      lib
    end

    private

    def read_classes(f, lib)
      f.while_match(/\A=[^=]/) do |line|
        type, name, _, superclass, = *line.sub(/\A=/, '').split
        type = type.intern
        case type
        when :class
          c = @db.define_class(name, superclass || 'Object', lib)
          read_class_body f, lib, c
        when :module
          compile_error "superclass given for module", line  if superclass
          m = @db.define_module(name, lib)
          read_class_body f, lib, m
        when :object
          o = @db.define_object(name, lib)
          read_entries f, lib, o, [:singleton_method]
        when :reopen
          c = name ? @db.get_class!(name) : nil
          read_class_body f, lib, c
        when :redefine
          c = name ? @db.get_class!(name) : nil
          read_class_body f, lib, c, true
        else
          compile_error "wrong level-1 header", line
        end
      end
    end

    def read_class_body(f, lib, klass, overwrite = false)
      f.skip_blank_lines
      f.while_match(/\Ainclude\s/) do |line|
        klass.include @db.get_class!(line.split[1])
      end
      f.skip_blank_lines
      klass.source = f.break(/\A=|\A---/).join('').rstrip
      read_entries f, lib, klass, nil, overwrite
      f.skip_blank_lines
      f.while_match(/\A==[^=]/) do |line|
        case line
        when /\A==\s*Class Method/i
          type = [:singleton_method]
        when /\A==\s*Private Class Method/i
          type = [:private_singleton_method]
        when /\A==\s*Instance Method/i
          type = [:instance_method]
        when /\A==\s*Private Instance Method/i
          type = [:private_instance_method]
        when /\A==\s*Module Function/i
          type = [:singleton_method, :private_instance_method]
        when /\A==\s*Constant/i
          type = [:constant]
        else
          compile_error "unknown level-2 header", line
        end
        read_entries f, lib, klass, type, overwrite
      end
    end

    def read_entries(f, lib, klass, types, overwrite = false)
      f.skip_blank_lines
      entries = []
      f.while_match(/\A---/) do |line|
        f.ungets line
        entries.push read_entry0(f, klass.name, types)
      end
      unify_identical_methods(entries).each do |ent0|
        add_method ent0, lib, overwrite
      end
    end

    def add_method(ent0, lib, overwrite)
      c = @db.get_class!(ent0.classname)
      ent0.types.each do |t|
        c.__send__("#{overwrite ? 'overwrite' : 'define'}_#{t}",
                   ent0.names, ent0.src, lib)
      end
    end

    def unify_identical_methods(entries)
      result = []
      entries.each do |entry|
        if result.empty?
          result.push entry
          next
        end
        last = result.last
        if last.classname == entry.classname and
              last.types == entry.types and
              not (last.names & entry.names).empty?
          result.push result.pop.unify(entry)
        else
          result.push entry
        end
      end
      result
    end

    def read_entry0(f, class0, types0)
      header = f.span(/\A---/)
      sigs = header.map {|line| method_signature(line, class0, types0) }
      c, t = sigs[0][0]
      first_ct = [c, t]
      if sigs.any? {|s| s[0] != first_ct }
        compile_error "alias entries have multiple class/type", header[0]
      end
      body = f.break(/\A(?:---|={1,2}[^=])/)
      src = (header + body).join('')
      Entry0.new(c, t, sigs.map {|s| s[1] }, src, header[0])
    end

    const = /[A-Z]\w*/
    cpath = /#{const}(?:::#{const})*/
    mid = /\w+[?!=]?|===|==|=~|<=|=>|<=>|\[\]=|\[\]|\*\*|>>|<<|\+@|\-@|[~+\-*\/%&|^<>]/
    SIGNATURE = /\A---\s*(?:(#{cpath})([\.\#]))?(#{mid})/

    def method_signature(line, class0, types0)
      m = SIGNATURE.match(line) or
          compile_error "cannot get method name", line
      if m[1]
        if class0
          compile_error "class context (#{class0}) exist but class specified again (#{m[1]})", line
        end
        [[m[1], m[2]], m[3]]
      else
        [[class0, types0], m[3]]
      end
    end

    class Entry0
      def initialize(classname, types, names, src, line)
        @classname = classname
        @types = types
        @names = names
        @src = src
        @line = line
      end

      attr_reader :classname
      attr_reader :types
      attr_reader :names
      attr_reader :src
      attr_reader :line

      def inspect
        "\#<Entry0 #{@classname} #{@types} #{@names.join(',')} #{@line.location}>"
      end

      def unify(other)
        Entry0.new(@classname, @types, (@names | other.names),
                   (@src + "\n" + other.src), @line)
      end
    end
  
  end


  class Preprocessor

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
          m = /\A\#@if\s*\((.*)\)\s*\z/.match(line) or
              compile_error "syntax error: wrong #@if", line
          last_if = line
          begin
            @cond_stack.push(@cond_stack.last && eval_cond(m[1]))
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

    def compile_error(msg, line)
      raise CompileError, "#{line.location}: #{msg}: #{line.inspect}"
    end

  end

end

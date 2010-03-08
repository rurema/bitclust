#
# bitclust/preprocessor.rb
#
# Copyright (c) 2006-2007 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

require 'bitclust/parseutils'
require 'strscan'

module BitClust

  class LineFilter

    include ParseUtils
    include Enumerable

    def initialize(f)
      @f = f
      @buf = []
    end

    def gets
      @buf.shift || next_line(@f)
    end

    def each
      while line = gets()
        yield line
      end
    end

    # abstract next_line

  end


  class Preprocessor < LineFilter

    def self.read(path, params = {})      
      if path.respond_to?(:gets)
        io = wrap(path, params)
      else
        io = wrap(fopen(path, 'r:EUC-JP'), params)
      end
      ret = ""
      while s = io.gets
        ret << s
      end
      ret
    end
    
    def Preprocessor.process(path, params = {})
      fopen(path, 'r:EUC-JP') {|f|
        return wrap(f, params).to_a
      }
    end

    def Preprocessor.wrap(f, params = {})
      new(LineStream.new(f), params)
    end

    def initialize(f, params = {})
      super f
      @params = params
      @last_if = nil
      cond_init
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
          next unless current_cond          
          begin
            file = $1.strip
            basedir = File.dirname(line.location.file)
            @buf.concat Preprocessor.process("#{basedir}/#{file}", @params)
          rescue Errno::ENOENT => err
            raise WrongInclude, "#{line.location}: \#@include'ed file not exist: #{file}"
          end
        when /\A\#@since\b/
          cond_stmt_begin line, build_cond_by_value(line, 'version >=')
        when /\A\#@until\b/
          cond_stmt_begin line, build_cond_by_value(line, 'version <')
        when /\A\#@if\b/
          cond_stmt_begin line, line.sub(/\A\#@if/, '').strip
        when /\A\#@else\s*\z/
          parse_error "no matching #@if", line  if cond_toplevel?
          cond_invert
        when /\A\#@end\s*\z/
          parse_error "no matching #@if", line  if cond_toplevel?
          cond_pop
        when /\A\#@/
          parse_error "unknown preprocessor directive", line
        else
          if current_cond
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

    def cond_stmt_begin(line, cond)
      @last_if = line
      begin
        cond_push eval_cond(cond)
      rescue ScanError => err
        parse_error err.message, line
      end
    end

    def build_cond_by_value(line, left)
      case ver = line.sub(/\A\#@\w+/, '').strip
      when /\A[\d\.]+\z/
        %Q(#{left} "#{ver}")
      when /\A"[\d\.]+"\z/
        "#{left} #{ver}"
      else
        parse_error "wrong conditional expr", line
      end
    end

    def current_cond
      @cond_stack.last
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
      val = eval_expr_p(s)
      while conj = read_conj(s)       
        case conj
        when 'and'
          val = eval_expr_p(s) && val
        when 'or'
          val = eval_expr_p(s) || val
        end
      end
      if paren_open
        unless s.skip(/\s*\)/)
          scan_error "paren opened but not closed"
        end
      end
      val
    end

    def eval_expr_p(s)
      val = eval_primary(s)
      while op = read_op(s)
        if op == '!='
          val = (val != eval_primary(s))
        else
          val = val.__send__(op, eval_primary(s))
        end
      end
      val 
    end

    def read_conj(s)
      s.skip(/\s+/)
      s.scan(/and|or/)
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


  class LineCollector < LineFilter

    def LineCollector.process(path)
      fopen(path) {|f|
        return wrap(f).to_a
      }
    end

    def LineCollector.wrap(f)
      new(LineStream.new(f))
    end

    private

    def next_line(f)
      while line = f.gets
        if /\A\#@include\s*\((.*?)\)/ =~ line
          begin
            file = $1.strip
            basedir = File.dirname(line.location.file)
            @buf.concat LineCollector.process("#{basedir}/#{file}")
          rescue Errno::ENOENT => err
            raise WrongInclude, "#{line.location}: \#@include'ed file not exist: #{file}"
          end
        else
          @buf.push line
        end
        break unless @buf.empty?
      end
      @buf.shift
    end

  end

end

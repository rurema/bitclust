# frozen_string_literal: true
#
# bitclust/preprocessor.rb
#
# Copyright (c) 2006-2007 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

require 'bitclust/compat'
require 'bitclust/parseutils'
require 'strscan'

module BitClust

  # Superclass of Preprocessor
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


  # Handle pragmas like #@todo, #@include, #@since, etc.
  #
  # bitclust#285: prefix は #% が正式(GitHub が #@since 等の @英字 を
  # ユーザー mention として解釈してしまうため)。旧 prefix #@ も、凍結タグ
  # (frozen-*)の旧ソースを再取込する場合に備えて引き続き受け付ける。
  class Preprocessor < LineFilter

    def self.read(path, params = {})
      if path.respond_to?(:gets)
        # @type var path: File
        io = wrap(path, params)
      else
        io = wrap(fopen(path, 'r:UTF-8'), params)
      end
      ret = +""
      while s = io.gets
        ret << s
      end
      ret
    end

    def Preprocessor.process(path, params = {})
      fopen(path, 'r:UTF-8') {|f|
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

    def path
      @f.path if @f.respond_to?(:path)
    end

    private

    def next_line(f)
      while line = f.gets
        case line
        when /\A(?!\#[@%])/
          if current_cond.processing?
            @buf.push line
            break
          end
        when /\A\#[@%]\#/   # preprocessor comment
          ;
        when /\A\#[@%]todo/i
          # 出力は prefix によらず @todo に正規化する(下流の表示処理は
          # 従来どおり @todo だけを見ればよい)
          @buf.push line.sub(/\A\#[@%]/, '@') if current_cond.processing?
        when /\A\#[@%]include\s*\((.*?)\)/
          next unless current_cond.processing?
          begin
            file = ($1 || raise).strip
            basedir = File.dirname(line.location.file || raise)
            path = "#{basedir}/#{file}"
            # md ツリーのネイティブパース: 断片は .md 拡張子付きで保存されるが
            # include ターゲットは元式の名前のまま（拡張子なしの pack-template、
            # .rd 付きの fiddle/2.0/fiddle.lib.rd 等）。md 側の実ファイル名を試す
            unless File.exist?(path)
              cand = ["#{path}.md", path.sub(/\.rd\z/, '.md')].find { |c| File.exist?(c) }
              path = cand if cand
            end
            @buf.concat Preprocessor.process(path, @params)
          rescue Errno::ENOENT => _err
            raise WrongInclude, "#{line.location}: \#@include'ed file not exist: #{file}"
          end
        when /\A\#[@%]since\b/
          cond_stmt_begin line, build_cond_by_value(line, 'version >=')
        when /\A\#[@%]until\b/
          cond_stmt_begin line, build_cond_by_value(line, 'version <')
        when /\A\#[@%]version\b/
          cond_stmt_begin line, build_cond_by_range(line)
        when /\A\#[@%]samplecode\b/
          samplecode_begin(line, samplecode_description_by_value(line))
        when /\A\#[@%]if\b/
          cond_stmt_begin line, line.sub(/\A\#[@%]if/, '').strip
        when /\A\#[@%]else\s*\z/
          parse_error "no matching \#@if", line  if cond_toplevel?
          cond_invert
        when /\A\#[@%]end\s*\z/
          if samplecode_processing?
            samplecode_end
          else
            parse_error "no matching \#@if", line  if cond_toplevel?
            cond_pop
          end
        else
          parse_error "unknown preprocessor directive", line
        end
      end
      if @buf.empty?
        unless cond_toplevel?
          parse_error "unterminated \#@if", @last_if || raise
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

    # 版範囲の省略記法(#285): #%version A...B は半開区間 [A, B)。
    # Ruby の終端排他 Range リテラルに合わせて3点ドット(.. は終端を含むと
    # 誤解しやすいため受け付けない)。A... は A 以上、...B は B 未満。
    # ドットなしの単一版 V はその版のみ(version == "V")。
    # 版はダブルクォート付きでもよい
    VERSION_LITERAL = /"(\d+(?:\.\d+)*)"|(\d+(?:\.\d+)*)/
    def build_cond_by_range(line)
      raw = line.sub(/\A\#[@%]version\b/, '').strip
      case raw
      when /\A#{VERSION_LITERAL}\.\.\.#{VERSION_LITERAL}\z/o
        %Q(version >= "#{$1 || $2}" and version < "#{$3 || $4}")
      when /\A#{VERSION_LITERAL}\.\.\.\z/o
        %Q(version >= "#{$1 || $2}")
      when /\A\.\.\.#{VERSION_LITERAL}\z/o
        %Q(version < "#{$1 || $2}")
      when /\A#{VERSION_LITERAL}\z/o
        %Q(version == "#{$1 || $2}")
      else
        parse_error "wrong version range (expected V / A...B / A... / ...B)", line
      end
    end

    def build_cond_by_value(line, left)
      case ver = line.sub(/\A\#[@%]\w+/, '').strip
      when /\A[\d\.]+\z/
        %Q(#{left} "#{ver}")
      when /\A"[\d\.]+"\z/
        "#{left} #{ver}"
      else
        parse_error "wrong conditional expr", line
      end
    end

    def current_cond
      @state_stack.last || raise
    end

    def cond_init
      @state_stack = [State.new(true, :toplevel)]
    end

    def cond_toplevel?
      @state_stack.size == 1
    end

    def cond_push(bool)
      last = @state_stack.last || raise
      @state_stack.push(last.next(bool, :condition))
    end

    def cond_invert
      b = (@state_stack.pop || raise).processing?
      last = @state_stack.last || raise
      @state_stack.push(last.next(!b, :condition))
    end

    def cond_pop
      @state_stack.pop
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
        unless @params.key?(t) # steep:ignore
          scan_error "database property `#{t}' not exist"
        end
        @params[t] # steep:ignore
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

    def samplecode_begin(line, description)
      description = description.strip
      samplecode_push(description)
      return unless current_cond.processing?
      @buf.push(+"//emlist[#{description}][ruby]{\n")
    end

    def samplecode_end
      samplecode_pop
      return unless current_cond.processing?
      @buf.push(+"//}\n")
    end

    def samplecode_push(description)
      last = @state_stack.last || raise
      @state_stack.push(last.next(true, :samplecode))
    end

    def samplecode_pop
      @state_stack.pop
    end

    def samplecode_processing?
      (@state_stack.last || raise).samplecode?
    end

    def samplecode_description_by_value(line)
      line.sub(/\A\#[@%]samplecode/, "")
    end

    def scan_error(msg)
      raise ScanError, msg
    end

    class State
      attr_reader :current

      def initialize(is_processing, label)
        @is_processing = is_processing
        @label = label
      end

      def next(is_processing, label)
        State.new(@is_processing && is_processing, label)
      end

      def toplevel?
        @label == :toplevel
      end

      def processing?
        @is_processing
      end

      def samplecode?
        @label == :samplecode
      end
    end
  end

  # Used by tools/stattodo.rb
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
        if /\A\#[@%]include\s*\((.*?)\)/ =~ line
          begin
            file = ($1 || raise).strip
            basedir = File.dirname(line.location.file || raise)
            @buf.concat LineCollector.process("#{basedir}/#{file}")
          rescue Errno::ENOENT => _err
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

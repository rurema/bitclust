#
# bitclust/rdcompiler.rb
#
# Copyright (C) 2006 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

require 'bitclust/lineinput'
require 'bitclust/textutils'
require 'stringio'

module BitClust

  class RDCompiler

    include TextUtils

    def initialize(hlevel = 1)
      @hlevel = hlevel
    end

    def compile(src)
      @f = f = LineInput.new(StringIO.new(src))
      @out = StringIO.new
      while f.next?
        f.while_match(/\A---/) do |line|
          compile_signature(line)
        end
        puts '<dd>'
        while f.next?
          case f.peek
          when /\A---/
            break
          when /\A=+/
            h f.gets
          when /\A\s+\*\s/
            ul
          when /\A\s+\(\d+\)\s/
            ol
          when %r<\A//emlist\{>
            emlist
          when /\A\s+\S/
            list
          else
            if f.peek.strip.empty?
              f.gets
            else
              paragraph
            end
          end
        end
        puts '</dd>'
      end
      @out.string
    end

    private

    def h(line)
      level = @hlevel + (line.slice(/\A=+/).size - 3)
      label = line.sub(/\A=+/, '').strip
      @out.puts "<h#{level}>#{escape_html(label)}</h#{level}>"
    end

    def ul
      puts '<ul>'
      @f.while_match(/\A\s+\*\s/) do |line|
        @out.print '<li>'
        @out.print compile_text(line.sub(/\A\s+\*/, '').strip)
        @f.while_match(/\A\s+[^\*\s]/) do |cont|
          @out.print "\n"
          @out.print compile_text(cont.strip)
        end
        @out.puts '</li>'
      end
      @out.puts '</ul>'
    end

    def ol
      puts '<ol>'
      @f.while_match(/\A\s+\(\d+\)/) do |line|
        @out.print '<li>'
        @out.print compile_text(line.sub(/\A\s+\(\d+\)/, '').strip)
        @f.while_match(/\A\s+(?!\(\d+\))\S/) do |cont|
          @out.print "\n"
          @out.print compile_text(cont.strip)
        end
        @out.puts '</li>'
      end
      @out.puts '</ol>'
    end

    def emlist
      @f.gets   # discard "//emlist{"
      @out.puts '<pre>'
      @f.until_terminator(%r<\A//\}>) do |line|
        @out.puts escape_html(line.rstrip)
      end
      @out.puts '</pre>'
    end

    def list
      lines = unindent_block(canonicalize(@f.break(/\A\S/)))
      while lines.last.empty?
        lines.pop
      end
      @out.puts '<pre>'
      lines.each do |line|
        @out.puts escape_html(line)
      end
      @out.puts '</pre>'
    end

    def canonicalize(lines)
      lines.map {|line| detab(line.rstrip) }
    end

    def paragraph
      @out.puts '<p>'
      @f.while_match(%r<\A(?!---|=|//\w)\S>) do |line|
        @out.puts compile_text(line.strip)
      end
      @out.puts '</p>'
    end

    def compile_signature(sig)
      # FIXME: check parameters, types, etc.
      @out.print '<dt>'
      @out.print escape_html(sig.sub(/\A---/, '').strip)
      @out.puts '</dt>'
    end

    BracketLink = /\[\[[!-~]+?\]\]/n
    NeedESC = /[&"<>]/

    def compile_text(str)
      escape_table = TextUtils::ESC
      str.gsub(/(#{NeedESC})|(#{BracketLink})/o) {
        if    char = $1 then escape_table[char]
        elsif tok  = $2 then bracket_link(tok[2..-3])
        elsif tok  = $3 then seems_code(tok)
        else
          raise 'must not happen'
        end
      }
    end

    def bracket_link(link)
      # FIXME
      escape_html("[[#{link}]]")
    end

    def seems_code(text)
      # FIXME
      escape_html(text)
    end

  end

end

#
# bitclust/rdcompiler.rb
#
# Copyright (C) 2006 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

require 'bitclust/lineinput'
require 'bitclust/htmlutils'
require 'bitclust/textutils'
require 'stringio'

module BitClust

  class RDCompiler

    include HTMLUtils
    include TextUtils

    def initialize(urlmapper, hlevel = 1)
      @urlmapper = urlmapper
      @hlevel = hlevel
    end

    def compile(src)
      @f = f = LineInput.new(StringIO.new(src))
      @out = StringIO.new
      while f.next?
        case f.peek
        when /\A---/
          method_list
        when /\A=+/
          headline f.gets
        when /\A\s+\*\s/
          ulist
        when /\A\s+\(\d+\)\s/
          olist
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
      @out.string
    end

    private

    def method_list
      @f.while_match(/\A---/) do |line|
        compile_signature(line)
      end
      @out.puts '<dd>'
      while @f.next?
        case @f.peek
        when /\A===+/
          headline @f.gets
        when /\A=/, /\A---/
          break
        when /\A\s+\*\s/
          ulist
        when /\A\s+\(\d+\)\s/
          olist
        when /\A:\s/
          dlist
        when %r<\A//emlist\{>
          emlist
        when /\A\s+\S/
          list
        else
          if @f.peek.strip.empty?
            @f.gets
          else
            paragraph
          end
        end
      end
      @out.puts '</dd>'
    end

    def headline(line)
      level = @hlevel + (line.slice(/\A=+/).size - 3)
      label = line.sub(/\A=+/, '').strip
      line h(level, escape_html(label))
    end

    def h(level, label)
      "<h#{level}>#{label}</h#{level}>"
    end

    def ulist
      @out.puts '<ul>'
      @f.while_match(/\A\s+\*\s/) do |line|
        string '<li>'
        string compile_text(line.sub(/\A\s+\*/, '').strip)
        @f.while_match(/\A\s+[^\*\s]/) do |cont|
          nl
          string compile_text(cont.strip)
        end
        line '</li>'
      end
      line '</ul>'
    end

    def olist
      @out.puts '<ol>'
      @f.while_match(/\A\s+\(\d+\)/) do |line|
        string '<li>'
        string compile_text(line.sub(/\A\s+\(\d+\)/, '').strip)
        @f.while_match(/\A\s+(?!\(\d+\))\S/) do |cont|
          string "\n"
          string compile_text(cont.strip)
        end
        line '</li>'
      end
      line '</ol>'
    end

    def dlist
      line '<dl>'
      @f.while_match(/\A:/) do |line|
        line dt(compile_text(line.sub(/\A:/, '').strip))
      end
      line '<dd>'
# FIXME: allow nested pre??
      @f.while_match(/\A(?:\s|\z)/) do |line|
        line compile_text(line.strip)
      end
      line '</dd>'
      line '</dl>'
    end

    def emlist
      @f.gets   # discard "//emlist{"
      line '<pre>'
      @f.until_terminator(%r<\A//\}>) do |line|
        line escape_html(line.rstrip)
      end
      line '</pre>'
    end

    def list
      lines = unindent_block(canonicalize(@f.break(/\A\S/)))
      while lines.last.empty?
        lines.pop
      end
      line '<pre>'
      lines.each do |line|
        line escape_html(line)
      end
      line '</pre>'
    end

    def canonicalize(lines)
      lines.map {|line| detab(line.rstrip) }
    end

    def paragraph
      line '<p>'
      @f.while_match(%r<\A(?!---|=|//\w)\S>) do |line|
        line compile_text(line.strip)
      end
      line '</p>'
    end

    def compile_signature(sig)
      # FIXME: check parameters, types, etc.
      string '<dt><code>'
      string escape_html(sig.sub(/\A---/, '').strip)
      line '</code></dt>'
    end

    BracketLink = /\[\[[!-~]+?\]\]/n
    NeedESC = /[&"<>]/

    def compile_text(str)
      escape_table = HTMLUtils::ESC
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
      type, arg = link.split(':', 2)
      case type
      when 'lib'     then library_link(arg)
      when 'c'       then class_link(arg)
      when 'm'       then method_link(complete_spec(arg))
      when 'man'     then escape_html(arg)   # FIXME
      when 'unknown' then escape_html(arg)
      else
        "[[#{escape_html(link)}]]"
      end
    end

    def complete_spec(spec0)
      case spec0
      when /\A\$/
        "Kernel#{spec0}"
      else
        spec0
      end
    end

    def seems_code(text)
      # FIXME
      escape_html(text)
    end

    def dt(s)
      "<dt>#{s}</dt>"
    end

    def string(str)
      @out.print str
    end

    def line(str)
      @out.puts str
    end

    def nl
      @out.puts
    end

  end

end

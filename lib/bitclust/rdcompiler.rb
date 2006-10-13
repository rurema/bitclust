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
      when 'url'     then direct_url(arg)
      when 'man'     then man_link(arg)
      when 'rfc', 'RFC'
        rfc_link(arg)
      when 'ruby-list', 'ruby-dev', 'ruby-ext', 'ruby-talk', 'ruby-core'
        blade_link(type, arg)
      else
        "[[#{escape_html(link)}]]"
      end
    end

    def direct_url(url)
      %Q(<a href="#{escape_html(url)}">#{escape_html(url)}</a>)
    end

    BLADE_URL = 'http://blade.nagaokaut.ac.jp/cgi-bin/scat.rb/ruby/%s/%s'

    def blade_link(ml, num)
      url = sprintf(BLADE_URL, ml, num)
      %Q(<a href="#{escape_html(url)}">[#{escape_html("#{ml}:#{num}")}]</a>)
    end

    RFC_URL = 'http://www.ietf.org/rfc/rfc%s.txt'

    def rfc_link(num)
      url = sprintf(RFC_URL, num)
      %Q(<a href="#{escape_html(url)}">[RFC#{escape_html(num)}]</a>)
    end

    opengroup_url = 'http://www.opengroup.org/onlinepubs/009695399'
    MAN_CMD_URL = "#{opengroup_url}/utilities/%s.html"
    MAN_FCN_URL = "#{opengroup_url}/functions/%s.html"

    def man_link(spec)
      m = /(\w+)\(([123])\)/.match(spec) or return escape_html(spec)
      url = sprintf((m[2] == '1' ? MAN_CMD_URL : MAN_FCN_URL), m[1])
      %Q(<a href="#{escape_html(url)}">#{escape_html("#{m[1]}(#{m[2]})")}</a>)
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

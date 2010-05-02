#
# bitclust/rdcompiler.rb
#
# Copyright (C) 2006-2008 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

require 'bitclust/methodsignature'
require 'bitclust/lineinput'
require 'bitclust/htmlutils'
require 'bitclust/textutils'
require 'stringio'

module BitClust

  class RDCompiler

    include HTMLUtils
    include TextUtils

    def initialize(urlmapper, hlevel = 1, opt = {})
      @urlmapper = urlmapper
      @catalog = opt[:catalog]
      @hlevel = hlevel
      @type = nil
      @library = nil
      @class = nil
      @method = nil
      @option = opt.dup
    end

    def compile(src)
      setup(src) {
        library_file
      }
    end

    # FIXME
    def compile_method(m, opt = nil)
      @opt = opt
      @type = :method
      @method = m
      setup(m.source) {
        method_entry
      }
    ensure
      @opt = nil
    end

    private

    def setup(src)
      @f = LineInput.new(StringIO.new(src))
      @out = StringIO.new
      yield
      @out.string
    end

    def library_file
      while @f.next?
        case @f.peek
        when /\A---/
          method_entry_chunk
        when /\A=+/
          headline @f.gets
        when /\A\s+\*\s/
          ulist
        when /\A\s+\(\d+\)\s/
          olist
        when %r<\A//emlist\{>
          emlist
        when /\A:\s/
          dlist
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
    end

    def method_entry
      while @f.next?
        method_entry_chunk
      end
    end

    def method_entry_chunk
      @out.puts '<dl>' if @option[:force]
      @f.while_match(/\A---/) do |line|
        method_signature line
      end
      props = {}
      @f.while_match(/\A:/) do |line|
        k, v = line.sub(/\A:/, '').split(':', 2)
        props[k.strip] = v.strip
      end
      @out.puts '<dd class="method-description">'
      while @f.next?
        case @f.peek
        when /\A===+/
          headline @f.gets
        when /\A==?/
          if @option[:force]
            break
          else
            raise "method entry includes headline: #{@f.peek.inspect}"
          end
        when /\A---/
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
        when /@see/
          see
        when /\A@[a-z]/
          method_info
        else
          if @f.peek.strip.empty?
            @f.gets
          else
            method_entry_paragraph
          end
        end
      end
      @out.puts '</dd>'
      @out.puts '</dl>' if @option[:force]
    end

    def headline(line)
      level = @hlevel + (line.slice(/\A=+/).size - 3)
      label = line.sub(/\A=+(\[a:(.*?)\])?/, '').strip
      frag = $2 if $2 and not $2.empty?
      line h(level, escape_html(label), frag)
    end

    def h(level, label, frag = nil)
      name = frag ? "id='#{escape_html(frag)}'" : ""
      "<h#{level} #{name}>#{label}</h#{level}>"
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
      while @f.next? and /\A:/ =~ @f.peek
        @f.while_match(/\A:/) do |line|
          line dt(compile_text(line.sub(/\A:/, '').strip))
        end
        dd_with_p
      end
      line '</dl>'
    end

    # empty lines separate paragraphs.
    def dd_with_p
      line '<dd>'
      while /\A(?:\s|\z)/ =~ @f.peek or %r!\A//emlist\{! =~ @f.peek
        case @f.peek
        when /\A$/
          @f.gets
        when  /\A[ \t\z]/
          line '<p>'
          @f.while_match(/\A[ \t\z]/) do |line|
            line compile_text(line.strip)
          end
          line '</p>'
        when %r!\A//emlist\{!
            emlist
        else
          raise 'must not happen'
        end
      end
      line '</dd>'
    end

    # empty lines do not separate paragraphs.
    def dd_without_p
      line '<dd>'
      while /\A[ \t]/ =~ @f.peek or %r!\A//emlist\{! =~ @f.peek
        case @f.peek
        when  /\A[ \t\z]/
          @f.while_match(/\A[ \t\z]/) do |line|
            line compile_text(line.strip)
          end
        when %r!\A//emlist\{!
            emlist
        end
      end
      line '</dd>'
    end

    def dt(s)
      "<dt>#{s}</dt>"
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
      read_paragraph(@f).each do |line|
        line compile_text(line.strip)
      end
      line '</p>'
    end

    def read_paragraph(f)
      f.span(%r<\A(?!---|=|//emlist\{)\S>)
    end

    def see
      header = @f.gets
      cmd = header.slice!(/\A\@\w+/)
      body = [header] + @f.span(/\A\s+\S/)
      line '<p>'
      line '[SEE_ALSO] ' + compile_text(body.join('').strip)
      line '</p>'
    end

    def method_info
      line '<dl>'
      while @f.next? and /\A\@(?!see)\w+|\A$/ =~ @f.peek
        header = @f.gets
        next if /\A$/ =~ header
        cmd = header.slice!(/\A\@\w+/)
        @f.ungets(header)
        case cmd
        when '@param', '@arg'
          name = header.slice!(/\A\s*\w+/n) || '?'
          line "<dt class='method-param'>[PARAM] #{escape_html(name.strip)}:</dt>"
        when '@raise'
          ex = header.slice!(/\A\s*[\w:]+/n) || '?'
          line "<dt>[EXCEPTION] #{escape_html(ex.strip)}:</dt>"
        when '@return'
          line "<dt>[RETURN]</dt>"
        else
          line "<dt>[UNKNOWN_META_INFO] #{escape_html(cmd)}:</dt>"
        end
        dd_without_p
      end
      line '</dl>'
    end

    # FIXME: parse @param, @return, ...
    def method_entry_paragraph
      line '<p>'
      read_method_entry_paragraph(@f).each do |line|
        line compile_text(line.strip)
      end
      line '</p>'
    end

    def read_method_entry_paragraph(f)
      f.span(%r<\A(?!---|=|//emlist\{|@[a-z])\S>)
    end

    def method_signature(sig_line)
      # FIXME: check parameters, types, etc.
      sig = MethodSignature.parse(sig_line)
      string '<dt class="method-heading"><code>'
      string @method.klass.name + @method.typemark if @opt
      string escape_html(sig.friendly_string)
      string '</code>'
      if @method and not @method.defined?
        line %Q( <span class="kindinfo">[#{@method.kind} by #{library_link(@method.library.name)}]</span>)
      end
      line '</dt>'
    end

    BracketLink = /\[\[[\w-]+?:[!-~]+?(?:\[\] )?\]\]/n
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

    def bracket_link(link, label = nil, frag = nil)
      type, _arg = link.split(':', 2)
      arg = _arg.rstrip
      case type
      when 'lib'
      then protect(link) {
          case arg
          when '/', '_index'
            label = 'All libraries'
          when '_builtin'
            label = 'Builtin libraries'
          end
          library_link(arg, label, frag)
        }
      when 'c'       then protect(link) { class_link(arg, label, frag) }
      when 'm'       then protect(link) { method_link(complete_spec(arg), label || arg, frag) }
      when 'f'
      then protect(link) {
          case arg
          when '/', '_index'
            arg, label = '', 'All C API'
          end
          function_link(arg, label || arg, frag)
        }
      when 'd'       then protect(link) { document_link(arg, label, frag) }
      when 'ref'     then protect(link) { reference_link(arg) }
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

    def protect(src)
      yield
    rescue => err
      %Q(<span class="compileerror">[[compile error: #{escape_html(err.message)}: #{escape_html(src)}]]</span>)
    end

    def direct_url(url)
      %Q(<a class="external" href="#{escape_html(url)}">#{escape_html(url)}</a>)
    end

    def reference_link(arg)
      case arg
      when /(\w+):(.*)\#(\w+)\z/
        type, name, frag = $1, $2, $3
        case type
        when 'lib'
          title, t, id = name, LibraryEntry.type_id.to_s, name
        when 'c'
          title, t, id = name, ClassEntry.type_id.to_s,   name
        when 'm'
          title, t, id = name, MethodEntry.type_id.to_s,  name
        when 'd'
          title, t, id = @option[:database].get_doc(name).title, DocEntry.type_id.to_s, name
        else
          raise "must not happen"
        end
        label = @option[:database].refs[t, id, frag]
        label = title + '/' + label if label and name
        bracket_link("#{type}:#{name}", label, frag)
      when /\A(\w+)\z/
        e = @option[:entry]
        frag = $1
        type = e.type_id.to_s
        label = @option[:database].refs[type, e.name, frag] || frag
        a_href('#' + frag, label)
      else
        raise "must not happen"
      end
    end

    BLADE_URL = 'http://blade.nagaokaut.ac.jp/cgi-bin/scat.rb/ruby/%s/%s'

    def blade_link(ml, num)
      url = sprintf(BLADE_URL, ml, num)
      %Q(<a class="external" href="#{escape_html(url)}">[#{escape_html("#{ml}:#{num}")}]</a>)
    end

    RFC_URL = 'http://www.ietf.org/rfc/rfc%s.txt'

    def rfc_link(num)
      url = sprintf(RFC_URL, num)
      %Q(<a class="external" href="#{escape_html(url)}">[RFC#{escape_html(num)}]</a>)
    end

    opengroup_url = 'http://www.opengroup.org/onlinepubs/009695399'
    MAN_CMD_URL = "#{opengroup_url}/utilities/%s.html"
    MAN_FCN_URL = "#{opengroup_url}/functions/%s.html"

    def man_link(spec)
      m = /(\w+)\(([123])\)/.match(spec) or return escape_html(spec)
      url = sprintf((m[2] == '1' ? MAN_CMD_URL : MAN_FCN_URL), m[1])
      %Q(<a class="external" href="#{escape_html(url)}">#{escape_html("#{m[1]}(#{m[2]})")}</a>)
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

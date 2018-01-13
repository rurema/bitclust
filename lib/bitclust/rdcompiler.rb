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
require 'bitclust/messagecatalog'
require 'bitclust/syntax_highlighter'
require 'stringio'

module BitClust

  # Compiles doc into HTML.
  class RDCompiler

    include HTMLUtils
    include TextUtils
    include Translatable

    def initialize(urlmapper, hlevel = 1, opt = {})
      @urlmapper = urlmapper
      @catalog = opt[:catalog]
      @hlevel = hlevel
      @type = nil
      @library = nil
      @class = nil
      @method = nil
      @option = opt.dup
      init_message_catalog(@catalog)
    end

    def compile(src)
      setup(src) {
        library_file
      }
    end

    def compile_function(f, opt = nil)
      @opt = opt
      @type = :function
      setup(f.source) {
        entry
      }
    ensure
      @opt = nil
    end

    # FIXME
    def compile_method(m, opt = nil)
      @opt = opt
      @type = :method
      @method = m
      setup(m.source) {
        entry
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
          entry_chunk
        when /\A=+/
          headline @f.gets
        when /\A(\s+)\*\s/, /\A(\s+)\(\d+\)\s/
          @item_stack = []
          item_list($1.size)
          raise "@item_stack should be empty. #{@item_stack.inspect}" unless @item_stack.empty?
        when %r<\A//emlist(?:\[(?:[^\[\]]+?)?\]\[\w+?\])?\{>
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

    def entry
      while @f.next?
        entry_chunk
      end
    end

    def entry_chunk
      @out.puts '<dl>' if @option[:force]
      first = true
      @f.while_match(/\A---/) do |line|
        method_signature(line, first)
        first = false
      end
      props = {}
      @f.while_match(/\A:/) do |line|
        k, v = line.sub(/\A:/, '').split(':', 2)
        props[k.strip] = v.strip
      end if @type == :method
      @out.puts %Q(<dd class="#{@type.to_s}-description">)
      while @f.next?
        case @f.peek
        when /\A===+/
          headline @f.gets
        when /\A==?/
          if @option[:force]
            break
          else
            raise "#{@type.to_s} entry includes headline: #{@f.peek.inspect}"
          end
        when /\A---/
          break
        when /\A(\s+)\*\s/, /\A(\s+)\(\d+\)\s/
          @item_stack = []
          item_list($1.size)
          raise "@item_stack should be empty. #{@item_stack.inspect}" unless @item_stack.empty?
        when /\A:\s/
          dlist
        when %r<\A//emlist(?:\[(?:[^\[\]]+?)?\]\[\w+?\])?\{>
          emlist
        when /\A\s+\S/
          list
        when /@see/
          see
        when /@todo/
          todo
        when /\A@[a-z]/
          entry_info
        else
          if @f.peek.strip.empty?
            @f.gets
          else
            entry_paragraph
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

    def item_list(level = 0, indent = true)
      open_tag = nil
      close_tag = nil
      case @f.peek
      when /\A(\s+)\*\s/
        open_tag  =  "<ul>"
        close_tag = "</ul>"
      when /\A(\s+)\(\d+\)\s/
        open_tag  = "<ol>"
        close_tag = "</ol>"
      end
      if indent
        line open_tag
        @item_stack.push(close_tag)
      end
      @f.while_match(/\A(\s+)(?:\*\s|\(\d+\))/) do |line|
        string "<li>"
        @item_stack.push("</li>")
        string compile_text(line.sub(/\A(\s+)(?:\*|\(\d+\))/, '').strip)
        if /\A(\s+)(?!\*\s|\(\d+\))\S/ =~ @f.peek
          @f.while_match(/\A\s+(?!\*\s|\(\d+\))\S/) do |cont|
            nl
            string compile_text(cont.strip)
          end
          line @item_stack.pop # current level li
        elsif /\A(\s+)(?:\*\s|\(\d+\))/ =~ @f.peek and level < $1.size
          item_list($1.size)
          line @item_stack.pop # current level ul or ol
        elsif /\A(\s+)(?:\*\s|\(\d+\))/ =~ @f.peek and level > $1.size
          line @item_stack.pop # current level li
          line @item_stack.pop # current level ul or ol
          line @item_stack.pop # previous level li
          item_list($1.size, false)
        else
          line @item_stack.pop # current level li
        end
      end
      line @item_stack.pop unless @item_stack.empty?
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
      while /\A(?:\s|\z)/ =~ @f.peek or %r!\A//emlist(?:\[(?:[^\[\]]+?)?\]\[\w+?\])?\{! =~ @f.peek
        case @f.peek
        when /\A$/
          @f.gets
        when  /\A[ \t\z]/
          line '<p>'
          @f.while_match(/\A[ \t\z]/) do |line|
            line compile_text(line.strip)
          end
          line '</p>'
        when %r!\A//emlist(?:\[(?:[^\[\]]+?)?\]\[\w+?\])?\{!
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
      while /\A[ \t]/ =~ @f.peek or %r!\A//emlist(?:\[(?:[^\[\]]+?)?\]\[\w+?\])?\{! =~ @f.peek
        case @f.peek
        when  /\A[ \t\z]/
          @f.while_match(/\A[ \t\z]/) do |line|
            line compile_text(line.strip)
          end
        when %r!\A//emlist(?:\[(?:[^\[\]]+?)?\]\[\w+?\])?\{!
          emlist
        end
      end
      line '</dd>'
    end

    def dt(s)
      "<dt>#{s}</dt>"
    end

    def emlist
      command = @f.gets
      if %r!\A//emlist\[(?<caption>[^\[\]]+?)?\]\[(?<lang>\w+?)\]! =~ command
        line "<pre class=\"highlight #{lang}\">"
        line "<span class=\"caption\">#{escape_html(caption)}</span>" if caption
        line "<code>"
        src = ""
        @f.until_terminator(%r<\A//\}>) do |line|
          src << line
        end
        if lang == "ruby"
          string BitClust::SyntaxHighlighter.new(src).highlight
        else
          string src
        end
        line '</code></pre>'
      else
        line '<pre>'
        @f.until_terminator(%r<\A//\}>) do |line|
          line escape_html(line.rstrip)
        end
        line '</pre>'
      end
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
      f.span(%r<\A(?!---|=|//emlist(?:\[(?:[^\[\]]+?)?\]\[\w+?\])?\{)\S>)
    end

    def see
      header = @f.gets
      cmd = header.slice!(/\A\@\w+/)
      body = [header] + @f.span(/\A\s+\S/)
      line '<p>'
      line '[SEE_ALSO] ' + compile_text(body.join('').strip)
      line '</p>'
    end

    def todo
      header = @f.gets
      cmd = header.slice!(/\A\@\w+/)
      body = header
      line '<p class="todo">'
      line '[TODO]' + body
      line '</p>'
    end

    def entry_info
      line '<dl>'
      while @f.next? and /\A\@(?!see)\w+|\A$/ =~ @f.peek
        header = @f.gets
        next if /\A$/ =~ header
        cmd = header.slice!(/\A\@\w+/)
        @f.ungets(header)
        case cmd
        when '@param', '@arg'
          name = header.slice!(/\A\s*\w+/) || '?'
          line "<dt class='#{@type.to_s}-param'>[PARAM] #{escape_html(name.strip)}:</dt>"
        when '@raise'
          ex = header.slice!(/\A\s*[\w:]+/) || '?'
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
    def entry_paragraph
      line '<p>'
      read_entry_paragraph(@f).each do |line|
        line compile_text(line.strip)
      end
      line '</p>'
    end

    def read_entry_paragraph(f)
      f.span(%r<\A(?!---|=|//emlist(?:\[(?:[^\[\]]+?)?\]\[\w+?\])?\{|@[a-z])\S>)
    end

    def method_signature(sig_line, first)
      # FIXME: check parameters, types, etc.
      sig = MethodSignature.parse(sig_line)
      string %Q(<dt class="method-heading")
      string %Q( id="#{@method.index_id}") if first
      string '><code>'
      string @method.klass.name + @method.typemark if @opt
      string escape_html(sig.friendly_string)
      string '</code>'
      if first
        string '<span class="permalink">['
        string a_href(@urlmapper.method_url(methodid2specstring(@method.id)), "permalink")
        string ']['
        string rdoc_link(@method.id, @option[:database].properties["version"])
        string ']</span>'
      end
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
        protect(link) {
          case arg
          when '/', '_index'
            label = 'All libraries'
          when '_builtin'
            label = 'Builtin libraries'
          end
          library_link(arg, label, frag)
        }
      when 'c'
        protect(link) { class_link(arg, label, frag) }
      when 'm'
        protect(link) { method_link(complete_spec(arg), label || arg, frag) }
      when 'f'
        protect(link) {
          case arg
          when '/', '_index'
            arg, label = '', 'All C API'
          end
          function_link(arg, label || arg, frag)
        }
      when 'd'
        protect(link) { document_link(arg, label, frag) }
      when 'ref'
        protect(link) { reference_link(arg) }
      when 'url'
        direct_url(arg)
      when 'man'
        man_link(arg)
      when 'rfc', 'RFC'
        rfc_link(arg)
      when 'ruby-list', 'ruby-dev', 'ruby-ext', 'ruby-talk', 'ruby-core'
        blade_link(type, arg)
      when 'feature', 'bug', 'misc'
        bugs_link(type, arg)
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
      %Q(<a class="external" target="_blank" rel="noopener" href="#{escape_html(url)}">#{escape_html(url)}</a>)
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
      %Q(<a class="external" target="_blank" rel="noopener" href="#{escape_html(url)}">[#{escape_html("#{ml}:#{num}")}]</a>)
    end

    RFC_URL = 'https://tools.ietf.org/html/rfc%s'

    def rfc_link(num)
      url = sprintf(RFC_URL, num)
      %Q(<a class="external" target="_blank" rel="noopener" href="#{escape_html(url)}">[RFC#{escape_html(num)}]</a>)
    end

    opengroup_url = 'http://www.opengroup.org/onlinepubs/009695399'
    MAN_CMD_URL = "#{opengroup_url}/utilities/%s.html"
    MAN_FCN_URL = "#{opengroup_url}/functions/%s.html"
    MAN_HEADER_URL = "#{opengroup_url}/basedefs/%s.html"
    MAN_LINUX_URL = "http://man7.org/linux/man-pages/man%1$s/%2$s.%1$s.html"
    MAN_FREEBSD_URL = "http://www.freebsd.org/cgi/man.cgi?query=%2$s&sektion=%1$s&manpath=FreeBSD+9.0-RELEASE"

    def man_url(section, page)
      case section
      when "1"
        sprintf(MAN_CMD_URL, page)
      when "2", "3"
        sprintf(MAN_FCN_URL, page)
      when "header"
        sprintf(MAN_HEADER_URL, page)
      when /\A([23457])linux\Z/
        sprintf(MAN_LINUX_URL, $1, page)
      when /\A([1-9])freebsd\Z/
        sprintf(MAN_FREEBSD_URL, $1, page)
      else
        nil
      end
    end

    def man_link(spec)
      m = /([\w\.\/]+)\((\w+)\)/.match(spec) or return escape_html(spec)
      url = man_url(m[2], escape_html(m[1])) or return escape_html(spec)
      %Q(<a class="external" target="_blank" rel="noopener" href="#{escape_html(url)}">#{escape_html("#{m[1]}(#{m[2]})")}</a>)
    end

    BUGS_URL = "https://bugs.ruby-lang.org/issues/%s"

    def bugs_link(type, id)
      url = sprintf(BUGS_URL, id)
      %Q(<a class="external" target="_blank" rel="noopener" href="#{escape_html(url)}">[#{type}##{id}]</a>)
    end

    def rdoc_url(method_id, version)
      cname, tmark, mname, libname = methodid2specparts(method_id)
      tchar = typemark2char(tmark) == 'i' ? 'i' : 'c'
      cname = cname.split(".").first
      cname = cname.gsub('::', '/')
      id = "method-#{tchar}-#{encodename_rdocurl(mname)}"

      "https://docs.ruby-lang.org/en/#{version}/#{cname}.html##{id}"
    end

    def rdoc_link(method_id, version)
      a_href(rdoc_url(method_id, version), "rdoc")
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

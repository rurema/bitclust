#
# bitclust/screen.rb
#
# Copyright (C) 2006-2007 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

require 'bitclust/rdcompiler'
require 'bitclust/htmlutils'
require 'bitclust/nameutils'
require 'erb'
require 'stringio'

module BitClust

  class ScreenManager
    def initialize(h)
      h[:template_repository]  = TemplateRepository.new(h.delete(:templatedir))
      h[:urlmapper] = URLMapper.new(h)
      @conf = h
    end

    def entry_screen(entry)
      new_screen(Screen.for_entry(entry), entry)
    end

    def library_index_screen(libs, opt = {})
      new_screen(LibraryIndexScreen, libs, opt)
    end

    def library_screen(lib, opt = {})
      new_screen(LibraryScreen, lib, opt)
    end

    def class_index_screen(cs, opt = {})
      new_screen(ClassIndexScreen, cs, opt)
    end

    def class_screen(c, opt = {:level => 0})
      new_screen(ClassScreen, c, opt)
    end

    def method_screen(ms, opt = {})
      new_screen(MethodScreen, ms, opt)
    end

    def seach_screen(result, opt = {})
      new_screen(SearchScreen, result, opt)
    end

    def doc_screen(d, opt = {})
      new_screen(DocScreen, d, opt)
    end
    
    def function_screen(f, opt = {})
      new_screen(FunctionScreen, f, opt)
    end

    def function_index_screen(fs, opt = {})
      new_screen(FunctionIndexScreen, fs, opt)
    end

    private

    def new_screen(c, *args)
      c.new(@conf, *args)
    end
  end


  class URLMapper
    include NameUtils

    def initialize(h)
      @base_url = h[:base_url]
      @cgi_url = h[:cgi_url]
      @css_url = h[:css_url]
      @theme = h[:theme] || 'default'
    end

    attr_reader :base_url

    def cgi_url
      @cgi_url
    end

    def css_url
      return @css_url if @css_url
      "#{@base_url}/theme/#{@theme}/style.css"
    end

    def library_index_url
      "#{@cgi_url}/library/"
    end

    def library_url(name)
      "#{@cgi_url}/library/#{libname2id(name)}"
    end

    def class_url(name)
      "#{@cgi_url}/class/#{classname2id(name)}"
    end

    def method_url(spec)
      cname, tmark, mname = *split_method_spec(spec)
      "#{@cgi_url}/method/#{classname2id(cname)}/#{typemark2char(tmark)}/#{encodename_url(mname)}"
    end

    def function_index_url
      "#{@cgi_url}/function/"
    end

    def function_url(name)
      "#{@cgi_url}/function/#{name}"
    end

    def spec_url(name)
      "#{@cgi_url}/spec/#{name}"
    end
    
    def document_url(name)
      raise unless %r!\A[\w/]+\z! =~ name
      "#{@cgi_url}/#{name}"
    end
  end


  class TemplateRepository
    def initialize(prefix)
      @prefix = prefix
    end

    def load(id)
      preproc(File.read("#{@prefix}/#{id}"))
    end

    private

    def preproc(template)
      template.gsub(/^\.include ([\w\-]+)/) { load($1.untaint) }.untaint
    end
  end


  class Screen
    def Screen.for_entry(entry)
      ent = entry.kind_of?(Array) ? entry.first : entry
      ::BitClust.const_get("#{ent.type_id.to_s.capitalize}Screen")
    end
  end

  class ErrorScreen < Screen
    include HTMLUtils

    def initialize(err)
      @error = err
    end

    def content_type
      'text/html'
    end

    def body
      <<-EndHTML
<html>
<head><title>Error</title></head>
<body>
<h1>Error</h1>
<pre>#{escape_html(@error.message)} (#{escape_html(@error.class.name)})
#{@error.backtrace.map {|s| escape_html(s) }.join("\n")}</pre>
</body>
</html>
      EndHTML
    end
  end

  class TemplateScreen < Screen
    include HTMLUtils

    def initialize(h)
      @urlmapper = h[:urlmapper]
      @template_repository = h[:template_repository]
      @default_encoding = h[:default_encoding]      
      @target_version = h[:database].propget('version')
      @conf = h
    end

    def content_type
      "text/html; charset=#{encoding()}"
    end

    def encoding
      default_encoding()
    end

    def ruby_version
      @target_version || 'unknown'
    end

    private

    def default_encoding
      @default_encoding || 'us-ascii'
    end

    def run_template(id)
      erb = ERB.new(@template_repository.load(id))
      erb.filename = id + '.erb'
      erb.result(binding())
    end

    def h(str)
      escape_html(str.to_s)
    end
    
    def css_url
      @urlmapper.css_url
    end

    def search_url
      "#{@urlmapper.cgi_url}/search"
    end
    
    def library_index_url
      @urlmapper.library_index_url
    end

    def function_index_url
      @urlmapper.function_index_url
    end

    def headline_init
      @hlevel = 1
    end

    def headline_push
      @hlevel += 1
    end

    def headline_pop
      @hlevel -= 1
    end

    def headline(str)
      "<h#{@hlevel}>#{escape_html(str)}</h#{@hlevel}>"
    end

    def headline_noescape(str)
      "<h#{@hlevel}>#{str}</h#{@hlevel}>"
    end

    def search_form
      if @conf[:tochm_mode]
        ""
      else
        %Q!<form method="get" action="#{h search_url()}" name="f" id="top_search"><input value="" name="q" size="15"> <input value="Search" type="submit"></form>!
      end
    end
    
    def compile_method(m)
      rdcompiler().compile_method(m)
    end

    def compile_function(f)
      compile_rd(f.source)
    end

    def compile_rd(src)
      rdcompiler().compile(src)
    end

    def rdcompiler
      RDCompiler.new(@urlmapper, @hlevel, @conf)
    end

    def foreach_method_chunk(src)
      f = LineInput.for_string(src)
      while f.next?
        sigs = f.span(/\A---/).map {|line| line.sub(/\A---\s+/, '').rstrip }
        body = f.break(/\A---/).join.split(/\n\n/, 2).first || ''
        yield sigs, body
      end
    end
  end

  class IndexScreen < TemplateScreen
    def initialize(h, entries, opt = {})
      h = h.dup
      h[:entries] = entries
      h[:database] = opt[:database]
      super h
      @entries = entries
    end

    def encoding
      return default_encoding() if @entries.empty?
      @entries.first.encoding
    end

    alias charset encoding
  end

  class EntryBoundScreen < TemplateScreen
    def initialize(h, entry, opt = {})
      h = h.dup
      h[:entry] = entry
      h[:database] = opt[:database]
      super h
      @entry = entry
    end

    def encoding
      @entry.encoding || default_encoding()
    end

    alias charset encoding
  end

  class LibraryIndexScreen < IndexScreen
    def body
      run_template('library-index')
    end
  end

  class LibraryScreen < EntryBoundScreen
    def body
      run_template('library')
    end
  end

  class ClassIndexScreen < IndexScreen
    def body
      run_template('class-index')
    end
  end

  class SearchScreen < IndexScreen
    def initialize(h, entries, opt = {})
      super h, entries, opt
      @query = opt[:q]
    end

    def body
      run_template('search')
    end
  end
  
  class ClassScreen < EntryBoundScreen
    def initialize(h, entry, opt = {})
      @alevel = opt[:level]
      super(h, entry, opt)
    end
    
    def body
      run_template('class')
    end
  end

  class MethodScreen < TemplateScreen
    def initialize(h, entries, opt = {})
      h = h.dup
      h[:database] = opt[:database]
      super h
      @entries = entries
    end

    def encoding
      ent = @entries.first
      ent ? ent.encoding : default_encoding()
    end

    alias charset encoding

    def body
      run_template('method')
    end
  end

  class FunctionScreen < EntryBoundScreen
    def body
      run_template('function')
    end
  end

  class FunctionIndexScreen < IndexScreen
    def body
      run_template('function-index')
    end
  end

  class DocScreen < EntryBoundScreen

    def encoding
      default_encoding()
    end
    alias charset encoding

    def body
      run_template('doc')
    end
    
    def rdcompiler
      h = {:force => true}.merge(@conf)
      RDCompiler.new(@urlmapper, @hlevel, h)
    end
  end
end

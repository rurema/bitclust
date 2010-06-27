#
# bitclust/screen.rb
#
# Copyright (C) 2006-2008 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

require 'bitclust/rdcompiler'
require 'bitclust/methodsignature'
require 'bitclust/htmlutils'
require 'bitclust/nameutils'
require 'bitclust/messagecatalog'
require 'erb'
require 'stringio'

module BitClust

  class ScreenManager
    def initialize(h)
      h[:urlmapper] ||= URLMapper.new(h)
      tmpldir = h[:templatedir] || "#{h[:datadir]}/template"
      h[:template_repository] ||= TemplateRepository.new(tmpldir)
      h[:message_catalog] ||= default_message_catalog(h)
      @conf = h
    end

    def default_message_catalog(h)
      dir = h[:catalogdir] || "#{h[:datadir]}/catalog"
      loc = MessageCatalog.encoding2locale(h[:encoding] || 'euc-jp')
      MessageCatalog.load_with_locales(dir, [loc])
    end
    private :default_message_catalog

    def entry_screen(entry, opt)
      new_screen(Screen.for_entry(entry), entry, opt)
    end

    def library_index_screen(libs, opt)
      new_screen(LibraryIndexScreen, libs, opt)
    end

    def library_screen(lib, opt)
      new_screen(LibraryScreen, lib, opt)
    end

    def class_index_screen(cs, opt)
      new_screen(ClassIndexScreen, cs, opt)
    end

    def class_screen(c, opt)
      new_screen(ClassScreen, c, opt)
    end

    def method_screen(ms, opt)
      new_screen(MethodScreen, ms, opt)
    end

    def opensearchdescription_screen(request_full_uri, opt)
      new_screen(OpenSearchDescriptionScreen, request_full_uri, opt)
    end

    def search_screen(result, opt)
      new_screen(SearchScreen, result, opt)
    end

    def doc_screen(d, opt)
      new_screen(DocScreen, d, opt)
    end
    
    def function_screen(f, opt)
      new_screen(FunctionScreen, f, opt)
    end

    def function_index_screen(fs, opt)
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
      @favicon_url = h[:favicon_url]
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

    def custom_css_url(css)
      "#{@base_url}/theme/#{@theme}/#{css}"
    end

    def js_url
      return @js_url if @js_url
      "#{@base_url}/theme/#{@theme}/t.js"
    end

    def custom_js_url(js)
      "#{@base_url}/theme/#{@theme}/#{js}"
    end

    def favicon_url
      return @favicon_url if @favicon_url
      "#{@base_url}/theme/#{@theme}/rurema.png"
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

    def opensearchdescription_url
      "#{@cgi_url}/opensearchdescription"
    end

    def search_url
      "#{@cgi_url}/search"
    end
    
    def spec_url(name)
      "#{@cgi_url}/spec/#{name}"
    end
    
    def document_url(name)
      raise unless %r!\A[-\w/]+\z! =~ name
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

    def status
      nil
    end
  end

  class ErrorScreen < Screen
    include HTMLUtils

    def initialize(err)
      @error = err
    end

    def status
      500
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

  class NotFoundScreen < Screen
    include HTMLUtils

    def initialize(err)
      @error = err
    end

    def status
      404
    end

    def content_type
      'text/html'
    end

    def body
      <<-EndHTML
<html>
<head><title>NotFound</title></head>
<body>
<h1>NotFound</h1>
<pre>#{escape_html(@error.message)} (#{escape_html(@error.class.name)})</pre>
</body>
</html>
      EndHTML
    end
  end

  class TemplateScreen < Screen
    include Translatable
    include HTMLUtils

    def initialize(h)
      @urlmapper = h[:urlmapper]
      @template_repository = h[:template_repository]
      @default_encoding = h[:default_encoding] || h[:database].propget('encoding')
      @target_version = h[:target_version] || h[:database].propget('version')
      init_message_catalog h[:message_catalog]
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

    def run_template(id, layout = true)
      method_name = "#{id}_template".gsub('-', '_')
      unless respond_to? method_name
        erb = ERB.new(@template_repository.load(id))
        erb.def_method(self.class, method_name, id + '.erb')
      end
      body = __send__(method_name)
      if layout
        unless respond_to? :layout
          erb = ERB.new(@template_repository.load('layout'))
          erb.def_method(self.class, 'layout', 'layout.erb')
        end
        layout{ body }
      else
        body
      end
    end

    def h(str)
      escape_html(str.to_s)
    end

    def css_url
      @urlmapper.css_url
    end

    def custom_css_url(css)
      @urlmapper.custom_css_url(css)
    end

    def js_url
      @urlmapper.js_url
    end

    def custom_js_url(js)
      @urlmapper.custom_js_url(js)
    end

    def favicon_url
      @urlmapper.favicon_url
    end

    def opensearchdescription_url
      @urlmapper.opensearchdescription_url
    end

    def search_url
      @urlmapper.search_url
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
        <<-EndForm
        <form method="get" action="#{h(search_url())}" name="top_search" id="top_search">
        <input value="" name="q" size="15">
        <input value="#{h(_('Search'))}" type="submit">
        </form>
        EndForm
      end
    end

    def manual_home_link
      document_link('index', _('Ruby %s Reference Manual', ruby_version()))
    end

    def friendly_library_link(id)
      library_link(id, friendly_library_name(id))
    end

    def friendly_library_name(id)
      (id == '_builtin') ? _('Builtin Library') : _('library %s', id)
    end
    
    def compile_method(m, opt = nil)
      rdcompiler().compile_method(m, opt)
    end

    def compile_function(f)
      compile_rd(f.source)
    end

    def compile_rd(src)
      rdcompiler().compile(src)
    end

    def rdcompiler
      opt = {:catalog => message_catalog()}.merge(@conf)
      RDCompiler.new(@urlmapper, @hlevel, opt)
    end

    def foreach_method_chunk(src)
      f = LineInput.for_string(src)
      while f.next?
        sigs = f.span(/\A---/).map {|line| MethodSignature.parse(line.rstrip) }
        body = f.break(/\A---/).join.split(/\n\n/, 2).first || ''
        yield sigs, body
      end
    end
  end

  class IndexScreen < TemplateScreen
    def initialize(h, entries, opt)
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
    def initialize(h, entry, opt)
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

  class OpenSearchDescriptionScreen < TemplateScreen
    def initialize(h, request_full_uri, opt)
      h = h.dup
      h[:database] = opt[:database]
      super h
      @search_full_url = (request_full_uri + search_url()).to_s
    end

    attr_reader :search_full_url

    def body
      run_template('opensearchdescription')
    end

    def content_type
      "application/opensearchdescription+xml; charset=#{encoding()}"
    end
  end

  class SearchScreen < IndexScreen
    def initialize(h, entries, opt)
      super h, entries, opt
      @query = opt[:q]
      @elapsed_time = opt[:elapsed_time]
    end

    def body
      run_template('search')
    end
  end
  
  class ClassScreen < EntryBoundScreen
    def initialize(h, entry, opt)
      @alevel = opt[:level] || 0
      super(h, entry, opt)
    end
    
    def body
      run_template('class')
    end
  end

  class MethodScreen < TemplateScreen
    def initialize(h, entries, opt)
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

    def body
      run_template('doc')
    end
    
    def rdcompiler
      h = {:force => true, :catalog => message_catalog() }.merge(@conf)
      RDCompiler.new(@urlmapper, @hlevel, h)
    end
  end
end

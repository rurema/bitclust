#
# bitclust/screen.rb
#
# Copyright (C) 2006 Minero Aoki
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
      @template = TemplateRepository.new(h.delete(:templatedir))
      @urlmapper = URLMapper.new(h)
    end

    def entity_screen(entity)
      new_screen(Screen.for_entity(entity), entity)
    end

    def library_index_screen(libs)
      new_screen(LibraryIndexScreen, libs)
    end

    def library_screen(lib)
      new_screen(LibraryScreen, lib)
    end

    def class_index_screen(cs)
      new_screen(ClassIndexScreen, cs)
    end

    def class_screen(c)
      new_screen(ClassScreen, c)
    end

    def method_screen(m)
      new_screen(MethodScreen, m)
    end

    private

    def new_screen(c, *args)
      c.new(@urlmapper, @template, *args)
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

    def library_url(id)
      "#{@cgi_url}/library/#{id}"
    end

    def class_url(id)
      "#{@cgi_url}/class/#{id.gsub(/::/, '__')}"
    end

    def method_url(c, t, m)
      "#{@cgi_url}/method/#{c.gsub(/::/, '__')}/#{typemark2char(t)}/#{fsencode(m)}"
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
    def Screen.for_entity(entity)
      ::BitClust.const_get("#{entity.type_id.to_s.capitalize}Screen")
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

    def initialize(urlmapper, template_repository)
      @urlmapper = urlmapper
      @template_repository = template_repository
    end

    def content_type
      "text/html; charset=#{encoding()}"
    end

    private

    def run_template(id)
      erb = ERB.new(@template_repository.load(id))
      erb.filename = id + '.erb'
      erb.result(binding())
    end

    alias h escape_html

    def css_url
      @urlmapper.css_url
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

    def compile_rd(src)
      RDCompiler.new(@urlmapper, @hlevel).compile(src)
    end
  end

  class IndexScreen < TemplateScreen
    def initialize(u, t, entities)
      super u, t
      @entities = entities
    end

    def encoding
      return 'us-ascii' if @entities.empty?
      @entities.first.encoding
    end

    alias charset encoding
  end

  class EntityBoundScreen < TemplateScreen
    def initialize(u, t, entity)
      super u, t
      @entity = entity
    end

    def encoding
      @entity.encoding || 'us-ascii'
    end

    alias charset encoding
  end

  class LibraryIndexScreen < IndexScreen
    def body
      run_template('library-index')
    end
  end

  class LibraryScreen < EntityBoundScreen
    def body
      run_template('library')
    end
  end

  class ClassIndexScreen < IndexScreen
    def body
      run_template('class-index')
    end
  end

  class ClassScreen < EntityBoundScreen
    def body
      run_template('class')
    end
  end

  class MethodScreen < EntityBoundScreen
    def body
      run_template('method')
    end
  end

end

#
# bitclust/screen.rb
#
# Copyright (C) 2006 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

require 'bitclust/urlmapper'
require 'bitclust/rdcompiler'
require 'bitclust/textutils'
require 'erb'
require 'stringio'

module BitClust

  class ScreenManager
    def initialize(h)
      @urlmapper = URLMapper.new(h[:baseurl])
      @params = Params.new(@urlmapper,
                           TemplateRepository.new(h[:templatedir]),
                           h[:theme] || 'default')
    end

    def entity_screen(entity)
      Screen.for_entity(entity).new(@params, entity)
    end

    def library_screen(lib)
      LibraryScreen.new(@params, lib)
    end

    def class_screen(c)
      ClassScreen.new(@params, c)
    end

    def method_screen(m)
      MethodScreen.new(@params, m)
    end

    class Params
      def initialize(umap, tmpl, theme)
        @urlmapper = umap
        @template_repository = tmpl
        @theme = theme
      end

      attr_reader :urlmapper
      attr_reader :template_repository

      def css_url
        "#{@theme}/style.css"
      end
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
    include TextUtils

    def Screen.for_entity(entity)
      ::BitClust.const_get("#{entity.type_id.to_s.capitalize}Screen")
    end

    def http_response
      body = body()
      out = StringIO.new
      out.puts "Content-Type: #{content_type()}"
      out.puts "Content-Length: #{body.length}"
      out.puts
      out.puts body
      out.string
    end
  end

  class ErrorScreen < Screen
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
    def initialize(params)
      @params = params
      @urlmapper = params.urlmapper
      @template_repository = params.template_repository
    end

    private

    def run_template(id)
      erb = ERB.new(@template_repository.load(id))
      erb.filename = id
      erb.result(binding())
    end

    alias h escape_html

    def css_url
      @params.css_url
    end
  end

  class EntityBoundScreen < TemplateScreen
    def initialize(params, entity)
      super params
      @entity = entity
    end

    def content_type
      "text/html; charset=#{@entity.encoding}"
    end

    def encoding
      @entity.encoding
    end

    alias charset encoding

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
      "<h#{@hlevel}>#{h(str)}</h#{@hlevel}>"
    end

    def compile_rd(src)
      RDCompiler.new(@hlevel).compile(src)
    end
  end

  class LibraryScreen < EntityBoundScreen
    def body
      run_template('library')
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

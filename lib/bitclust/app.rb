require 'bitclust'
require 'bitclust/interface'

module BitClust

  class App

    def initialize(options)
      @options = options
      dbpath = options[:dbpath]
      baseurl = options[:baseurl] || ''
      datadir = options[:datadir] || File.expand_path('../../data/bitclust', File.dirname(__FILE__))
      encoding = options[:encoding] || 'euc-jp'
      viewpath = options[:viewpath]
      capi = options[:capi]
      if options[:rack]
        request_handler_class = BitClust::RackRequestHandler
      else
        request_handler_class = BitClust::RequestHandler
      end
      @interfaces = {}
      case dbpath
      when String
        dbpath = File.expand_path(dbpath)
        db = BitClust::MethodDatabase.new(dbpath)
        if capi
          db = [db, BitClust::FunctionDatabase.new(dbpath)]
        end
        manager = BitClust::ScreenManager.new(
          :base_url => baseurl,
          :cgi_url => File.join(baseurl, viewpath),
          :datadir => datadir,
          :templatedir => options[:templatedir],
          :theme => options[:theme],
          :encoding => encoding
          )
        handler = request_handler_class.new(db, manager)
        @interfaces[viewpath] = BitClust::Interface.new { handler }
      when Array
        dbpaths = dbpath
        @versions = []
        dbpaths.each do |dbpath|
          next unless /db-([\d_]+)/ =~ dbpath
          dbpath = File.expand_path(dbpath)
          version = $1.tr("_", ".")
          @versions << version
          if viewpath
            version_viewpath = File.join(version, viewpath)
          else
            version_viewpath = version
          end
          db = BitClust::MethodDatabase.new(dbpath)
          if capi
            db = [db, BitClust::FunctionDatabase.new(dbpath)]
          end
          manager = BitClust::ScreenManager.new(
            :base_url => baseurl,
            :cgi_url => File.join(baseurl, version_viewpath),
            :datadir => datadir,
            :templatedir => options[:templatedir],
            :theme => options[:theme],
            :encoding => encoding
            )
          handler = request_handler_class.new(db, manager)
          @interfaces[version_viewpath] = BitClust::Interface.new { handler }
          $bitclust_context_cache = nil # clear cache
        end
      end
    end

    attr_reader :interfaces, :versions

    def index(req)
      case
      when @interfaces.size == 1 && viewpath = @options[:viewpath]
        # Redirect from '/' to "#{viewpath}/"
        @index = "<html><head><meta http-equiv='Refresh' content='0;URL=#{viewpath}'></head></html>"
      when 1 < @interfaces.size
        request_path = case
                       when req.respond_to?(:path_info)
                         req.path_info
                       when req.respond_to?(:path)
                         req.path_info
                       end
        if @versions.any?{|version| %r|\A/?#{version}/?\z| =~ request_path }
          viewpath = File.join(request_path, @options[:viewpath])
          @index = "<html><head><meta http-equiv='Refresh' content='0;URL=#{viewpath}'></head></html>"
        else
          links = "<ul>"
          @interfaces.keys.sort.each do |v|
            if @options[:viewpath]
              version = v.sub(@options[:viewpath], '')
            else
              version = v
            end
            url = v
            links << %Q(<li><a href="#{url}/">#{version}</a></li>)
          end
          links << "</ul>"
          if File.exist?("readme.html")
            @index = File.read("readme.html").sub(%r!\./bitclust!, '').sub(/<!--links-->/) { links }
          else
            @index = "<html><head><title>bitclust</title></head><body>#{links}</body></html>"
          end
        end
      end
    end

    def get_instance(server)
      self
    end

    def service(req, res)
      unless  %r|/#{File.basename(@options[:baseurl])}/?\z| =~ req.path
        raise WEBrick::HTTPStatus::NotFound
      end
      res.body = index(req)
      res['Content-Type'] = 'text/html; charset=euc-jp'
    end

    def call(env)
      [
        200,
        {'Content-Type' => 'text/html; charset=euc-jp'},
        index(Rack::Request.new(env))
      ]
    end
  end
end

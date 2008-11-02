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
      if options[:rack]
        request_handler_class = BitClust::RackRequestHandler
      else
        request_handler_class = BitClust::RequestHandler
      end
      if viewpath
        dbpath = File.expand_path(dbpath)
        db = BitClust::MethodDatabase.new(dbpath)
        manager = BitClust::ScreenManager.new(
          :base_url => baseurl,
          :cgi_url => "#{baseurl}/#{viewpath}",
          :datadir => datadir,
          :encoding => encoding
          )
        handler = request_handler_class.new(db, manager)
        @interfaces = {
          viewpath => BitClust::Interface.new { handler }
        }
      else
        @interfaces = {}
        dbpaths = dbpath
        dbpaths.each do |dbpath|
          next unless /db-([\d_]+)/ =~ dbpath
          dbpath = File.expand_path(dbpath)
          version = $1.tr("_", ".")
          db = BitClust::MethodDatabase.new(dbpath)
          manager = BitClust::ScreenManager.new(
            :base_url => baseurl,
            :cgi_url => "#{baseurl}/#{version}",
            :datadir => datadir,
            :encoding => encoding
            )
          handler = request_handler_class.new(db, manager)
          @interfaces[version] = BitClust::Interface.new { handler }
          $bitclust_context_cache = nil # clear cache
        end
      end
    end

    attr_reader :interfaces

    def index
      case
      when defined?(@index)
        return @index
      when viewpath = @options[:viewpath]
        # Redirect from '/' to "#{viewpath}/"
        @index = "<html><head><meta http-equiv='Refresh' content='0;URL=#{viewpath}'></head></html>"
      when defined?(@interfaces)
        links = "<ul>"
        @interfaces.keys.sort.each do |version|
          links << %Q(<li><a href="#{version}/">#{version}</a></li>)
        end
        links << "</ul>"
        if File.exist?("readme.html")
          @index = File.read("readme.html").sub(%r!\./bitclust!, '').sub(/<!--links-->/) { links }
        else
          @index = "<html><head><title>bitclust</title></head><body>#{links}</body></html>"
        end
      end
    end

    def get_instance(server)
      self
    end

    def service(req, res)
      raise WEBrick::HTTPStatus::NotFound if req.path != '/'
      res.body = index
      res['Content-Type'] = 'text/html; charset=euc-jp'
    end

    def call(env)
      [
        200,
        {'Content-Type' => 'text/html; charset=euc-jp'},
        index
      ]
    end
  end
end

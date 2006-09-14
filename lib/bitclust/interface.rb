#
# bitclust/interface.rb
#
# Copyright (c) 2006 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

require 'webrick/cgi'
begin
  require 'fcgi'
rescue LoadError
end

module BitClust

  class Interface

    def initialize(webrick_conf = {})
      @webrick_conf = webrick_conf
      @handler = ($bitclust_context_cache ||= yield)
    end

    def main
      if fastcgi?
        FCGI.new(@webrick_conf).main(@handler)
      else
        # CGI, mod_ruby
        CGI.new(@webrick_conf).main(@handler)
      end
    end

    private

    def fastcgi?
      defined?(::FCGI) and ::FCGI.fastcgi?
    end

    def mod_ruby?
      false   # FIXME
    end

    class CGI < ::WEBrick::CGI
      def main(handler)
        @handler = handler
        start
      end

      def do_GET(wreq, wres)
        @handler.handle(wreq).update wres
      end

      alias do_POST do_GET
    end

    class FCGI < CGI
      def main(handler)
        @handler = handler
        ::FCGI.each_cgi_request do |req|
          start req.env, req.in, req.out
        end
      end
    end
  
  end

end

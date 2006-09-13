#
# bitclust/requesthandler.rb
#
# Copyright (c) 2006 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

unless Object.method_defined?(:funcall)
  class Object
    alias funcall __send__
  end
end

module BitClust

  class RequestHandler

    def initialize(db, manager)
      @db = db
      @screenmanager = manager
    end

    def cgi_main
      screen = handle(CGI.new)
      print screen.http_response
    end

    # FIXME: not implemented yet
    #def fcgi_main
    #end

    def handle(webrick_req)
      res = _handle(Request.new(webrick_req))
    rescue WEBrick::HTTPStatus::Status
      raise
    rescue => err
      return error_response(err)
    end

    private

    def _handle(req)
      unless req.type_id
        raise RequestError, "no type id"
      end
      mid = "handle_#{req.type_id}"
      unless respond_to?(mid, true)
        raise RequestError, "wrong request: type=#{req.type_id}"
      end
      funcall(mid, req)
    end

    def error_response(err)
      ErrorScreen.new(err)
    end

    def handle_library(req)
      name = req.library_name
      lib = @db.lookup_library(name)
      @screenmanager.library_screen(lib)
    end

    def handle_class(req)
      name = req.class_name
      c = @db.lookup_class(name)
      @screenmanager.class_screen(c)
    end

    def handle_method(req)
      spec = req.method_spec
      method = @db.lookup_method(*spec)
      @screenmanager.method_screen(method)
    end

    def handle_search(key)
      # FIXME
    end

  end


  class Request

    def initialize(wreq)
      @wreq = wreq
    end

    def library?
      type_id() == :library
    end

    def class?
      type_id() == :class
    end

    def method?
      type_id() == :method
    end

    def library_name
      return nil unless library?
      type_param()
    end

    def class_name
      return nil unless class?
      type_param()
    end

    def method_spec
      return nil unless method?
      param = type_param()
      return nil unless param
      c, t, m = param.split('/', 3)
      return nil unless c
      return nil unless t
      return nil unless m
      return nil unless /\A[\w+\:\-]+\z/ =~ c
      type =
          case t
          when 'i' then :imethod
          when 's' then :smethod
          when 'c' then :constant
          when 'v' then :svar
          else
            nil
          end
      [c, type, m]
    end

    def type_id
      type, param = parse_path_info()
      case t = type.intern
      when :library, :class, :method
        t
      else
        nil
      end
    end

    private

    def type_param
      type, param = parse_path_info()
      return nil unless param
      return nil if param.empty?
      param
    end

    def parse_path_info
      return nil unless @wreq.path_info
      _, type, param = @wreq.path_info.split('/', 3)
      return nil unless param
      return nil if param.empty?
      return type, param
    end

  end

end

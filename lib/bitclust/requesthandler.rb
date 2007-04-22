#
# bitclust/requesthandler.rb
#
# Copyright (c) 2006-2007 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

require 'bitclust/compat'
require 'bitclust/screen'
require 'bitclust/methodid'
require 'bitclust/nameutils'

module BitClust

  class RequestHandler

    def initialize(db, manager)
      @db = db
      @screenmanager = manager
    end

    def handle(webrick_req)
      _handle(Request.new(webrick_req))
    rescue WEBrick::HTTPStatus::Status
      raise
    rescue => err
      return error_response(err)
    end

    private

    def _handle(req)
      return library_index() unless req.type_id
      mid = "handle_#{req.type_id}"
      unless respond_to?(mid, true)
        raise RequestError, "wrong request: type_id=#{req.type_id}"
      end
      funcall(mid, req)
    end

    def error_response(err)
      ErrorScreen.new(err).response
    end

    def handle_library(req)
      return library_index() unless req.library_name
      lib = @db.fetch_library(req.library_name)
      @screenmanager.library_screen(lib).response
    end

    def handle_class(req)
      return class_index() unless req.class_name
      c = @db.fetch_class(req.class_name)
      @screenmanager.class_screen(c).response
    end

    def handle_method(req)
      ms = @db.fetch_methods(req.method_spec)
      @screenmanager.method_screen(ms).response
    end

    def library_index
      @screenmanager.library_index_screen(@db.libraries.sort).response
    end

    def class_index
      @screenmanager.class_index_screen(@db.classes.sort).response
    end

    def handle_search(key)
      # FIXME
    end

  end


  class Request

    include NameUtils

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
      raise '#library_name called but not library request' unless library?
      id = type_param()
      return nil unless id
      name = libid2name(id)
      unless libname?(name)
        raise InvalidKey, "invalid library name: #{name.inspect}"
      end
      name
    end

    def class_name
      raise '#class_name called but not class request' unless class?
      id = type_param()
      return nil unless id
      name = classid2name(id)
      unless classname?(name)
        raise InvalidKey, "invalid class name: #{name.inspect}"
      end
      name
    end

    def method_spec
      return nil unless method?
      param = type_param()
      return nil unless param
      cid, typechar, mencoded = param.split('/', 3)
      raise InvalidKey, 'missing class name' unless cid
      raise InvalidKey, 'missing type name' unless typechar
      raise InvalidKey, 'missing method name' unless mencoded
      unless typechar?(typechar)
        raise InvalidKey, "invalid method-type ID: #{typechar.inspect}"
      end
      cname = classid2name(cid)
      tmark = typechar2mark(typechar)
      mname = decodename_url(mencoded)
      unless classname?(cname)
        raise InvalidKey, "invalid class name: #{cname.inspect}"
      end
      case tmark
      when '$'
        unless gvarname?('$' + mname)
          raise InvalidKey, "invalid variable name: #{('$' + mname).inspect}"
        end
      when '.', '#', '.#', '::'
        unless methodname?(mname)
          raise InvalidKey, "invalid method name: #{mname.inspect}"
        end
      end
      MethodSpec.new(cname, tmark, mname)
    end

    def type_id
      type, param = parse_path_info()
      case type
      when 'library', 'class', 'method'
        type.intern
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
      param = nil if not param or param.empty?
      return type, param
    end

  end


  class Screen   # reopen
    def response
      Response.new(self)
    end
  end


  class Response

    def initialize(screen)
      @screen = screen
    end

    def update(webrick_res)
      # webrick_res.status = @status if @status
      webrick_res['Content-Type'] = @screen.content_type
      # webrick_res['Last-Modified'] = @screen.last_modified
      body = @screen.body
      webrick_res['Content-Length'] = body.length
      webrick_res.body = body
    end

  end

end

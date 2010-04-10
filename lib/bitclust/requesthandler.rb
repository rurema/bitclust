#
# bitclust/requesthandler.rb
#
# Copyright (c) 2006-2008 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

require 'bitclust/compat'
require 'bitclust/screen'
require 'bitclust/methodid'
require 'bitclust/nameutils'
require 'bitclust/simplesearcher'

module BitClust

  class RequestHandler

    def initialize(db, manager)
      if db.is_a? Array
        @db, @cdb = db
      else
        @db = db
      end
      @screenmanager = manager
      @conf = { :database => @db }
    end

    def handle(webrick_req)
      _handle(Request.new(webrick_req))
    rescue WEBrick::HTTPStatus::Status
      raise
    rescue BitClust::NotFoundError => err
      return not_found_response(err)
    rescue => err
      return error_response(err)
    end

    private

    def _handle(req)
      return handle_doc(req) unless req.defined_type?
      mid = "handle_#{req.type_id}"
      unless respond_to?(mid, true)
        raise RequestError, "wrong request: type_id=#{req.type_id}"
      end
      funcall(mid, req)
    end

    def error_response(err)
      ErrorScreen.new(err).response
    end

    def not_found_response(err)
      NotFoundScreen.new(err).response
    end

    def handle_library(req)
      return library_index() unless req.library_name
      lib = @db.fetch_library(req.library_name)
      @screenmanager.library_screen(lib, @conf).response
    end

    def handle_class(req)
      return class_index() unless req.class_name
      c =  @db.fetch_class(req.class_name)
      h = @conf.dup
      h[:level] = req.ancestors_level
      @screenmanager.class_screen(c, h).response
    end

    def handle_method(req)
      ms = @db.fetch_methods(req.method_spec)
      raise MethodNotFound.new(req.method_spec.to_s) if ms.nil? || ms.empty?
      @screenmanager.method_screen(ms, @conf).response
    end

    def library_index
      @screenmanager.library_index_screen(@db.libraries.sort, @conf).response
    end

    def class_index
      @screenmanager.class_index_screen(@db.classes.sort, @conf).response
    end

    def handle_opensearchdescription(req)
      @screenmanager.opensearchdescription_screen(req.full_uri, @conf).response
    end

    def handle_search(req)
      ret = []
      q0 = req.query['q'] || ''
      q = URI.unescape(q0)
      start = Time.now.to_i
      ret = SimpleSearcher.search_pattern(@db, q)
      elapsed_time = Time.now.to_f - start.to_f
      c = @conf.dup
      c[:q] = q0
      c[:elapsed_time] = elapsed_time
      @screenmanager.search_screen(ret, c).response
    end

    def handle_doc(req)
      d = @db.fetch_doc(req.doc_name || 'index' )
      @screenmanager.doc_screen(d, @conf).response
    end
    
    def handle_function(req)
      return function_index() unless req.function_name
      f = @cdb.fetch_function(req.function_name)
      @screenmanager.function_screen(f, @conf).response
    end

    def function_index
      @screenmanager.function_index_screen(@cdb.functions.sort, @conf).response
    end

  end

  class RackRequestHandler < RequestHandler
    def handle(rack_req)
      _handle(RackRequest.new(rack_req))
    rescue BitClust::NotFoundError => err
      return not_found_response(err)
    rescue => err
      return error_response(err)
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

    def doc_name
      name = path_info.sub(%r!\A/!, '')
      name unless name.empty?
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

    def defined_type?
      type, param = parse_path_info()
      case type
      when 'library', 'class', 'method', 'function', 'search', 'opensearchdescription'
        true
      else
        false
      end
    end

    def type_id
      type, param = parse_path_info()
      type.intern if type
    end

    def function?
      type_id() == :function
    end

    def function_name
      raise '#function_name called but not function request' unless function?
      id = type_param()
      return nil unless id
      name = id
      unless functionname?(name)
        raise InvalidKey, "invalid function name: #{name.inspect}"
      end
      name
    end

    def ancestors_level
      ret = query['a'].to_i
      if ret < 0
        0
      else
        ret
      end
    end

    def query
      @wreq.query
    end

    def full_uri
      @wreq.request_uri
    end

    private

    def type_param
      type, param = parse_path_info()
      return nil unless param
      return nil if param.empty?
      param
    end

    def parse_path_info
      return nil unless path_info
      _, type, param = path_info.split('/', 3)
      param = nil if not param or param.empty?
      return type, param
    end

    def path_info
      @wreq.path_info
    end

  end

  class RackRequest < Request

    def initialize(rack_req)
      @rack_req = rack_req
    end

    def query
      @rack_req.params
    end

    def path_info
      @rack_req.env["PATH_INFO"]
    end

    def full_uri
      URI.parse(@rack_req.url)
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
      webrick_res.status = @screen.status if @screen.status
      webrick_res['Content-Type'] = @screen.content_type
      # webrick_res['Last-Modified'] = @screen.last_modified
      body = @screen.body
      webrick_res['Content-Length'] = body.bytesize
      webrick_res.body = body
    end

    def rack_finish
      [
        @screen.status || 200,
        {
          'Content-Type' => @screen.content_type,
        },
        @screen.body
      ]
    end

  end

end

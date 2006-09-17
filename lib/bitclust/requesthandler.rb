#
# bitclust/requesthandler.rb
#
# Copyright (c) 2006 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

require 'bitclust/screen'
require 'bitclust/database'
require 'bitclust/nameutils'

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

    def handle(webrick_req)
      _handle(Request.new(webrick_req))
    rescue WEBrick::HTTPStatus::Status
      raise
    rescue => err
      return error_response(err)
    end

    private

    def _handle(req)
      mid = "handle_#{req.type_id || :library}"
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
      return class_index() unless req.method_spec
      m = @db.fetch_method(req.method_spec)
      @screenmanager.method_screen(m).response
    end

    def library_index
      @screenmanager.library_index_screen(@db.sorted_libraries).response
    end

    def class_index
      @screenmanager.class_index_screen(@db.sorted_classes).response
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
      c = c.gsub(/__/, '::')
      return nil unless /\A[\w+\:]+\z/ =~ c
      return nil unless /\A[simcv]\z/ =~ t
      # m is going to be encoded
      SearchPattern.for_ctm(c, typechar2mark(t), m)
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

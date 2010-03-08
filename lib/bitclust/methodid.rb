#
# bitclust/methodid.rb
#
# Copyright (c) 2006-2007 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

require 'bitclust/compat'
require 'bitclust/nameutils'
require 'bitclust/exception'

module BitClust

  # A MethodID has #library, #klass, #typename, and method name.
  # #library, #klass, #typename must be an object.
  class MethodID
    include NameUtils

    def initialize(library = nil, klass = nil, type = nil, name = nil)
      @library = library
      @klass = klass
      @type = type
      @name = name
    end

    attr_accessor :library
    attr_accessor :klass
    attr_accessor :type
    attr_accessor :name

    def inspect
      "#<methodid #{@library.name}.#{@klass.name}#{typemark()}#{@name}>"
    end

    def match?(m)
      m.name == @name and
      m.type == @type and
      m.library == @library
    end

    alias typename type

    def typechar
      typename2char(@type)
    end

    def typemark
      typename2mark(@type)
    end

    def idstring
      build_method_id(@library.id, @klass.id, @type, @name)
    end
  end


  # A MethodSpec has #klass, #type, #method and #library.
  # All attributes are string.
  # #library is optional.
  class MethodSpec

    def MethodSpec.parse(str)
      new(*NameUtils.split_method_spec(str))
    end

    def initialize(c, t, m, library = nil)
      @klass = c
      @type = t
      @method = m
      @library = library
    end

    attr_reader :klass
    attr_reader :type
    attr_reader :method
    attr_reader :library

    def inspect
      "#<spec #{@klass}#{@type}#{@method}>"
    end

    def to_s
      "#{@klass}#{@type}#{@method}"
    end

    def display_name
      @type == '$' ? "$#{@method}" : to_s()
    end

    def ==(other)
      @klass == other.klass and
      @type == other.type and
      @method == other.method
    end

    alias eql? ==

    def hash
      to_s().hash
    end

    def <=>(other)
      [@klass, @type, @method] <=> [other.klass, other.type, other.method]
    end

    def match?(m)
      (not @type or @type == m.typemark) and
      (not @method or m.name?(@method))
    end

    def singleton_method?
      @type == '.' or @type == '.#'
    end

    def instance_method?
      @type == '#' or @type == '.#'
    end

    def module_function?
      @type == '.#'
    end

    def method?
      singleton_method? or instance_method?
    end

    def constant?
      @type == '::'
    end

    def special_variable?
      @type == '$'
    end

  end


  # A MethodNamePattern has #klass, #type, #method and #library.
  # All attributes are string.
  # All attributes are optional.
  class MethodNamePattern

    def initialize(c = nil, t = nil, m = nil, lib = nil)
      @klass = c
      if c and c.empty?
        @klass = nil
      end
      @type = t
      @method = m
      if m and m.empty?
        @method = nil
      end
      @library = library
      @crecache = []
      @mrecache = []
    end

    attr_reader :klass
    attr_reader :type
    attr_reader :method
    attr_reader :library

    def inspect
      "#<pattern #{esc(@library)}.#{esc(@klass)}#{tesc(@type)}#{esc(@method)}>"
    end

    def esc(s)
      s || '_'
    end
    private :esc

    def tesc(s)
      s || ' _ '
    end
    private :tesc

    def match?(m)
      (not @library or m.library.name?(@library)) and
      (not @klass   or m.klass.name?(@klass)) and
      (not @type    or m.typemark == @type) and
      (not @method  or m.name?(@method))
    end

    def select_classes(cs)
      return cs unless @klass
      expand_ic(cs, @klass, @crecache)
    end

    def empty?
      not @klass and not @type and not @method
    end

    def class?
      @klass and (not @type and not @method)
    end

    def method?
      @method or (@type and @type != '$')
    end

    def special_variable?
      @type == '$'
    end

  end

end

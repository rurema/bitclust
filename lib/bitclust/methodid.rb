#
# bitclust/methodid.rb
#
# Copyright (c) 2006 Minero Aoki
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
      m.library == @library and
      m.type == @type and
      m.name == @name
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

    def ==(other)
      @klass == other.klass and
      @type == other.type and
      @method == other.method
    end

    alias eql? ==

    def hash
      to_s().hash
    end

    def match?(m)
      (not @type or @type == m.typemark) and
      (not @method or m.name?(@method))
    end

  end

end

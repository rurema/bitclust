require 'bitclust/exception'

module BitClust

  class Database

    def initialize(prefix)
      @prefix = prefix
      @libraries = []
      @classes = []
    end

    attr_reader :libraries
    attr_reader :classes

    def add_library(lib)
      # FIXME: check duplication
      @libraries.push lib
    end

    def define_class(name, supername, lib)
      define_c(:class, name, get_class!(supername), lib)
    end

    def define_module(name, lib)
      define_c(:module, name, nil, lib)
    end

    def define_object(name, lib)
      define_c(:object, name, nil, lib)
    end

    def define_c(type, name, superclass, lib)
      c = ClassDescription.new(:class, name, superclass)
      # FIXME: check duplication
      @classes.push c
      lib.add_class c
      c.library = lib
      c
    end
    private :define_c

    def get_library(name)
    end

    def get_library!(name)
    end

    def get_class(name)
      @classes.detect {|c| c.name == name }
    end

    def get_class!(name)
get_class(name) or ForwardLibrary.new(name)
    end

    #def methods  ??

  end


  class ForwardLibrary
    def initialize(name)
      @name = name
    end
  end


  class LibraryDescription

    include Enumerable

    def initialize(name, requires, src)
      @name = name
      @requires = []
      @source = src
      @classes = []    # DEFINED classes
      @methods = []    # DEFINED methods
    end

    attr_reader :name
    attr_reader :requires
    attr_reader :source
    attr_reader :classes
    attr_reader :methods

    def each_class(&block)
      @classes.each(&block)
    end

    def each_method(&block)
      @methods.each(&block)
    end

    def require(lib)
      @requires.push lib
    end

    def add_class(c)
      @classes.push c
    end

    def add_method(m)
      @methods.push m
    end

  end


  # Represents classes, modules and singleton objects.
  class ClassDescription

    def initialize(type, name, superclass)
      @type = type   # :class | :module | :object
      @name = name
      @superclass = superclass
      @included = []
      @singleton_methods = []
      @s_table = {}
      @instance_methods = []
      @i_table = {}
      @constants = []
      @source = nil
      @library = nil
    end

    attr_reader :type
    attr_reader :name
    attr_reader :superclass
    attr_reader :included
    attr_reader :singleton_methods
    attr_reader :instance_methods
    attr_reader :constants
    attr_accessor :source
    attr_accessor :library

    def inspect
      "\#<#{@type} #{@name}>"
    end

    def class?
      @type == :class
    end

    def module?
      @type == :module
    end

    def object?
      @type == :object
    end

    def entries
      @singleton_methods + @instance_methods + @constants
    end

    def singleton_method_names
      @s_table.keys
    end

    def instance_method_names
      @i_table.keys
    end

    def include(m)
      @included.push m
    end

    def define_singleton_method(names, src, lib)
      t = @singleton_methods
      m = make_mdesc(:method, names, src, lib)
      define @singleton_methods, @s_table, m
      m
    end

    def define_private_singleton_method(names, src, lib)
      t = @singleton_methods
      m = make_mdesc(:method, names, src, lib)
      m.private
      define @singleton_methods, @s_table, m
      m
    end

    def define_instance_method(names, src, lib)
      t = @instance_methods
      m = make_mdesc(:method, names, src, lib)
      define @instance_methods, @i_table, m
    end

    def define_private_instance_method(names, src, lib)
      t = @instance_methods
      m = make_mdesc(:method, names, src, lib)
      m.private
      define @instance_methods, @i_table, m
    end

    def define_constant(names, src, lib)
      t = @singleton_methods
      m = make_mdesc(:constant, names, src, lib)
      define @singleton_methods, @s_table, m
      m
    end

    def overwrite_singleton_method(names, src, lib)
      t = @singleton_methods
      m = make_mdesc(:method, names, src, lib)
      overwrite @singleton_methods, m
      m
    end

    def overwrite_private_singleton_method(names, src, lib)
      t = @singleton_methods
      m = make_mdesc(:method, names, src, lib)
      m.private
      overwrite @singleton_methods, m
      m
    end

    def overwrite_instance_method(names, src, lib)
      t = @instance_methods
      m = make_mdesc(:method, names, src, lib)
      overwrite @instance_methods, m
      m
    end

    def overwrite_private_instance_method(names, src, lib)
      t = @instance_methods
      m = make_mdesc(:method, names, src, lib)
      m.private
      overwrite @instance_methods, m
      m
    end

    def make_mdesc(type, names, src, lib)
      m = MethodDescription.new(self, type, names, src)
      m.library = lib
      lib.add_method m
      m
    end

    private

    def define(list, table, m)
      m.names.each do |n|
        m2 = table[n]
        if m2 and m2.library != m.library
          raise CompileError, "method #{n} provided from multiple libraries: #{m.library.name} and #{m2.library.name}"
        end
        table[n] = m
      end
      list.push m
    end

    def overwrite(methods, m)
      raise 'FIXME'
    end

  end


  # Represents methods, constants and special variables.
  class MethodDescription

    def initialize(klass, type, names, src)
      @class = klass
      @type = type
      @names = names
      @source = src
      @library = nil
    end

    attr_reader :class
    attr_reader :type
    attr_reader :names
    attr_reader :source
    attr_accessor :library

    def inspect
      "\#<#{@type} #{@names.join(',')}>"
    end

    def document_html
      raise 'not implemented'
    end

  end

end

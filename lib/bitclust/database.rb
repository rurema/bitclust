#
# bitclust/database.rb
#
# Copyright (c) 2006 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

require 'bitclust/nameutils'
require 'bitclust/exception'
require 'fileutils'

module BitClust

  class MethodSpec
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
      "#<spec #{@library.name}.#{@klass.name}#{typemark()}#{@name}>"
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

    def id
      build_method_id(@library.id, @klass.id, @type, @name)
    end
  end


  class SearchPattern

    def SearchPattern.for_ctm(c, t, m)
      new(nil, c, t, m)
    end

    def initialize(lib = nil, c = nil, t = nil, m = nil)
      @library = library
      @klass = c
      @type = t
      @method = m
    end

    attr_reader :library
    attr_reader :klass
    attr_reader :type
    attr_reader :method

    def inspect
      "#<spec #{@library}.#{@klass}#{@type}#{@method}>"
    end

    def match?(m)
      (not @library or m.library.name == @library) and
      (not @type    or m.typemark     == @type)    and
      (not @method  or m.names.include?(@method))
    end

  end


  class Database

    def Database.dummy
      new(nil)
    end

    def initialize(prefix)
      @prefix = prefix
      @properties = nil
      @librarymap = nil
      @classmap = nil
      @in_transaction = false
      @properties_dirty = false
      @dirty_entities = {}
    end

    def dummy?
      not @prefix
    end

    def init
      FileUtils.rm_rf @prefix
      FileUtils.mkdir_p @prefix
      Dir.mkdir "#{@prefix}/library"
      Dir.mkdir "#{@prefix}/class"
      Dir.mkdir "#{@prefix}/method"
      FileUtils.touch "#{@prefix}/properties"
    end

    def transaction
      @in_transaction = true
      yield
      return if dummy?
      if @properties_dirty
        save_string_map 'properties', @properties
        @properties_dirty = false
      end
      @dirty_entities.each_key do |x|
        x.save
      end
      @dirty_entities.clear
    ensure
      @in_transaction = false
    end

    def check_transaction
      return if dummy?
      unless @in_transaction
        raise NotInTransaction, "data written without transaction"
      end
    end
    private :check_transaction

    def dirty(x)
      @dirty_entities[x] = true
    end

    alias dirty_library dirty
    alias dirty_class   dirty
    alias dirty_method  dirty

    def properties
      @properties ||= load_string_map('properties')
    end
    private :properties

    def libraries
      librarymap().values
    end

    def librarymap
      @librarymap ||= load_extent(LibraryEntry)
    end
    private :librarymap

    def classes
      classmap().values
    end

    def classmap
      @classmap ||= load_extent(ClassEntry)
    end
    private :classmap

    def load_extent(klass)
      h = {}
      entries(klass.type_id).each do |ent|
        h[ent] = klass.new(self, ent)
      end
      h
    end
    private :load_extent

    def entries(rel)
      Dir.entries(fullpath(rel)).reject {|ent| ent[0,1] == '.' }
    rescue Errno::ENOENT
      []
    end

    # internal use only
    def load_entities(rel, klass)
      read(rel).split.map {|id| klass.load(self, id) }
    end

    # internal use only
    def save_entities(rel, xs)
      write rel, xs.map {|x| x.id + "\n" }.join('')
    end

    # internal use only
    def load_string_map(rel)
      h = {}
      read(rel).each do |line|
        k, v = line.strip.split('=', 2)
        h[k] = v
      end
      h
    end

    # internal use only
    def save_string_map(rel, h)
      write rel, h.map {|k,v| "#{k}=#{v}\n" }.join('')
    end

    # internal use only
    def exist?(rel)
      File.exist?(fullpath(rel))
    end

    # internal use only
    def makepath(rel)
      FileUtils.mkdir_p fullpath(rel)
    end

    # internal use only
    def read(rel)
      File.read(fullpath(rel))
    rescue Errno::ENOENT
      raise unless dummy?
      return ''
    end

    # internal use only
    def write(rel, str)
      tmppath = fullpath(rel) + '.writing'
      File.open(tmppath, 'w') {|f|
        f.write str
      }
      File.rename tmppath, fullpath(rel)
    ensure
      begin
        File.unlink tmppath
      rescue
      end
    end

    # internal use only
    def fullpath(rel)
      "#{@prefix}/#{rel}"
    end

    def propkeys
      properties().keys
    end

    def propget(key)
      properties()[key]
    end

    def propset(key, value)
      check_transaction
      properties()[key] = value
      @properties_dirty = true
    end

    def encoding
      propget('encoding')
    end

    def update_by_file(path, libname)
      check_transaction
      RRDParser.new(self).parse_file(path, libname, properties())
    end

    def open_library(name, reopen = false)
      check_transaction
      table = librarymap()
      if lib = table[name]
        lib.clear unless reopen
      else
        table[name] = lib = LibraryEntry.new(self, name)
      end
      dirty_library lib
      lib
    end

    def open_class(name)
      check_transaction
      table = classmap()
      if c = table[name]
        c.clear
      else
        table[name] = c = ClassEntry.new(self, name)
      end
      yield c
      dirty_class c
      c
    end

    # FIXME: see kind
    def open_method(spec)
      check_transaction
      if m = spec.klass.search_method(spec)
        m.clear
      else
        m = MethodEntry.new(self, spec.id)
        spec.klass.add_method m
      end
      m.library = spec.library
      m.klass   = spec.klass
      m.type    = spec.type
      yield m
      dirty_method m
      m
    end

    def get_library(name)
      librarymap()[name] ||= LibraryEntry.new(self, name)
    end

    def fetch_library(name)
      librarymap()[name] or
          raise EntityNotFound, "library not found: #{name.inspect}"
    end

    def get_class(name)
      classmap()[name] ||= ClassEntry.new(self, name)
    end

    def fetch_class(name)
      classmap()[name] or
          raise EntityNotFound, "class not found: #{name.inspect}"
    end

    def fetch_methods(spec)
      fetch_class(spec.klass).search_methods(spec)
    end

    def fetch_method(spec)
      fetch_class(spec.klass).search_method(spec)
    end

  end


  class Entity

    include NameUtils

    class << self
      alias load new
    end

    def self.property(name)
      module_eval(<<-End, __FILE__, __LINE__ + 1)
        def #{name}
          load_props(load_properties()) unless @#{name}
          @#{name}
        end

        attr_writer :#{name}
      End
    end

    def initialize(db)
      @db = db
    end

    def type_id
      self.class.type_id
    end

    def encoding
      @db.encoding
    end

    def source
      @source ||= db_read('source')
    end

    attr_writer :source

    def save
      @db.makepath objpath()
      save_properties save_props()
      db_write 'source', @source if @source
      _save
    end

    private

    def saved?
      @db.exist?(objpath())
    end

    def load_properties
      @db.load_string_map(objpath('properties'))
    end

    def save_properties(h)
      @db.save_string_map(objpath('properties'), h)
    end

    def restore_library(id)
      LibraryEntry.load(@db, id)
    end

    def restore_class(id)
      id.empty? ? nil : ClassEntry.load(@db, id)
    end

    def restore_libraries(str)
      restore_entities(str, LibraryEntry)
    end

    def restore_classes(str)
      restore_entities(str, ClassEntry)
    end

    def restore_methods(str)
      restore_entities(str, MethodEntry)
    end

    def restore_entities(str, klass)
      str.split(',').map {|id| klass.load(@db, id) }
    end

    def serialize_entity(x)
      x ? x.id : ''
    end

    def serialize_entities(xs)
      xs.map {|x| x.id }.join(',')
    end

    def db_read(rel)
      @db.read(objpath(rel))
    end

    def db_write(rel, src)
      @db.write objpath(rel), src
    end

    def objpath(rel = nil)
      "#{type_id()}/#{id()}#{rel ? '/' : ''}#{rel}"
    end

  end


  class LibraryEntry < Entity

    include Enumerable

    def LibraryEntry.type_id
      :library
    end

    def initialize(db, name)
      super db
      @name = name
      if saved?
        @requires = nil
        @source = nil
        @classmap = nil    # includes only DEFINED classes
        @methodmap = nil   # includes only DEFINED methods
      else
        clear
      end
    end

    def clear
      @requires  = []
      @source    = '(should be initialized)'
      @classmap  = {}
      @methodmap = {}
    end

    attr_reader :name

    def id
      libname2id(@name)
    end

    def inspect
      "#<library c=#{classnames().join(',')} m=#{methodnames().join(',')}>"
    end

    property :requires

    def load_props(h)
      @requires = restore_libraries(h['requires'])
    end
    private :load_props

    def save_props
      {'requires' => serialize_entities(requires())}
    end
    private :save_props

    def require(lib)
      requires().push lib
    end

    def classnames
      classmap().keys
    end

    def each_class(&block)
      classmap().each_value(&block)
    end

    def classes
      classmap().values
    end

    def classmap
      @classmap ||=
          begin
            h = {}
            load_classes().each do |c|
              h[c.name] = c
            end
            h
          end
    end
    private :classmap

    def methodnames
      methods().map {|m| m.label }
    end

    def methods
      methodmap().values
    end

    def each_method(&block)
      methodmap().each_key(&block)
    end

    def methodmap
      @methodmap ||=
          begin
            h = {}
            load_methods().each do |m|
              h[m] = m
            end
            h
          end
    end
    private :methodmap

    def _save
      save_classes classes()  if @classmap
      save_methods methods()  if @methodmap
    end
    private :_save

    def add_class(c)
      unless classmap()[c.name]
        classmap()[c.name] = c
        @db.dirty_library self
      end
    end

    def add_method(m)
      unless methodmap()[m]
        methodmap()[m] = m
        @db.dirty_library self
      end
    end

    private

    def load_classes
      @db.load_entities(objpath('classes'), ClassEntry)
    end

    def save_classes(cs)
      @db.save_entities objpath('classes'), cs
    end

    def load_methods
      @db.load_entities(objpath('methods'), MethodEntry)
    end

    def save_methods(ms)
      @db.save_entities objpath('methods'), ms
    end

  end


  # Represents classes, modules and singleton objects.
  class ClassEntry < Entity

    include Enumerable

    def ClassEntry.type_id
      :class
    end

    def initialize(db, name)
      super db
      @name = name
      if saved?
        @type       = nil   # :class | :module | :object
        @library    = nil
        @superclass = nil
        @included   = nil
        @extended   = nil
        @source     = nil
        @entries    = nil
      else
        clear
      end
    end

    def clear
      @type       = :unknown
      @library    = :unknown
      @superclass = :unknown
      @included   = []
      @extended   = []
      @source     = '(should be initialized)'
      @entries    = load_methods()
    end

    attr_reader :name

    def id
      classname2id(@name)
    end

    property :type
    property :superclass
    property :included
    property :extended
    property :library

    def load_props(h)
      @type       = h['type'].intern
      @superclass = restore_class(h['superclass'])
      @included   = restore_classes(h['included'])
      @extended   = restore_classes(h['extended'])
    end
    private :load_props

    def save_props
      { 'type'       => @type.to_s,
        'superclass' => serialize_entity(@superclass),
        'included'   => serialize_entities(@included),
        'extended'   => serialize_entities(@extended) }
    end
    private :save_props

    def entries
      @entries ||= load_methods()
    end

    def _save
      save_methods  if @entries
    end
    private :_save

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

    def include(m)
      included().push m
    end

    def extend(m)
      extended().push m
    end

    def each(&block)
      entries().each(&block)
    end

    def search_methods(spec)
      entries().select {|m| spec.match?(m) }
    end

    def search_method(spec)
      entries().detect {|m| spec.match?(m) }
    end

    def add_method(m)
      # FIXME: check duplication?
      entries().push m
    end

    private

    def load_methods
      @db.entries("method/#{id()}")\
          .map {|ent| MethodEntry.new(@db, "#{id()}/#{ent}") }
    end

    def save_methods
      # FIXME: find removed methods and remove them.
    end

  end


  # Represents methods, constants, and special variables.
  class MethodEntry < Entity

    def MethodEntry.type_id
      :method
    end

    def initialize(db, id)
      super db
      @id = id
      @names = nil
      @library = nil
      @klass = nil
      @type = nil    # :singleton_method | :instance_method | :module_function
                     #    | :constant | :special_variable
      @visibility = nil   # :public | :private | :protected
      @kind = nil    # :defined | :added | :redefined
      @source = nil
    end

    attr_reader :id

    def name
      names().first
    end

    property :names
    property :library
    property :klass
    property :type
    property :visibility
    property :kind

    def load_props(h)
      @names      = h['names'].split(',')
      @library    = restore_library(h['library'])
      @klass      = restore_class(h['klass'])
      @type       = h['type'].intern
      @visibility = h['visibility'].intern
      @kind       = h['kind'].intern
    end
    private :load_props

    def save_props
      { 'names'      => @names.join(','),
        'library'    => @library.id,
        'klass'      => @klass.id,
        'type'       => @type.to_s,
        'visibility' => @visibility.to_s,
        'kind'       => @kind.to_s }
    end
    private :save_props

    def _save
    end
    private :_save

    def inspect
      "\#<method #{klass().name}#{typemark()}#{@names.join(',')}>"
    end

    def label
      "#{klass().name}#{typemark()}#{name()}"
    end

    def typemark
      typename2mark(type())
    end

    def singleton_method?
      @type == :singleton_method or @type == :module_function
    end

    def instance_method?
      @type == :instance_method or @type == :module_function
    end

    def constant?
      @type == :constant
    end

    def special_variable?
      @type == :special_variable
    end

  end

end

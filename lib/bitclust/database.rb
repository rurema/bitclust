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

    include NameUtils

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
      @dirty_entries = {}
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

    #
    # Transaction
    #

    def transaction
      @in_transaction = true
      yield
      return if dummy?
      if @properties_dirty
        save_properties 'properties', @properties
        @properties_dirty = false
      end
      @dirty_entries.each_key do |x|
        x.save
      end
      @dirty_entries.clear
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
      @dirty_entries[x] = true
    end

    alias dirty_library dirty
    alias dirty_class   dirty
    alias dirty_method  dirty

    def update_by_file(path, libname)
      check_transaction
      RRDParser.new(self).parse_file(path, libname, properties())
    end

    #
    # Properties
    #

    def properties
      @properties ||= load_properties('properties')
    end
    private :properties

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

    #
    # Libraries
    #

    def libraries
      librarymap().values
    end

    def librarymap
      @librarymap ||= load_extent(LibraryEntry)
    end
    private :librarymap

    def get_library(name)
      librarymap()[name] ||= LibraryEntry.new(self, libname2id(name))
    end

    def fetch_library(name)
      librarymap()[name] or
          raise EntryNotFound, "library not found: #{name.inspect}"
    end

    def open_library(name, reopen = false)
      check_transaction
      table = librarymap()
      if lib = table[name]
        lib.clear unless reopen
      else
        table[name] = lib = LibraryEntry.new(self, libname2id(name))
      end
      dirty_library lib
      lib
    end

    #
    # Classes
    #

    def classes
      classmap().values
    end

    def classmap
      @classmap ||= load_extent(ClassEntry)
    end
    private :classmap

    def get_class(name)
      classmap()[name] ||= ClassEntry.new(self, classname2id(name))
    end

    def fetch_class(name)
      classmap()[name] or
          raise EntryNotFound, "class not found: #{name.inspect}"
    end

    def open_class(name)
      check_transaction
      table = classmap()
      if c = table[name]
        c.clear
      else
        table[name] = c = ClassEntry.new(self, classname2id(name))
      end
      yield c
      dirty_class c
      c
    end

    def load_extent(klass)
      h = {}
      entries(klass.type_id).each do |ent|
        h[ent] = klass.new(self, ent)
      end
      h
    end
    private :load_extent

    #
    # Methods
    #

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

    def fetch_methods(spec)
      fetch_class(spec.klass).search_methods(spec)
    end

    def fetch_method(spec)
      fetch_class(spec.klass).search_method(spec)
    end

    #
    # Direct File Access (Internal use only)
    #

    def exist?(rel)
      File.exist?(realpath(rel))
    end

    def entries(rel)
      Dir.entries(realpath(rel)).reject {|ent| ent[0,1] == '.' }
    rescue Errno::ENOENT
      []
    end

    def makepath(rel)
      FileUtils.mkdir_p realpath(rel)
    end

    def load_properties(rel)
      h = {}
      File.open(realpath(rel)) {|f|
        while line = f.gets
          k, v = line.strip.split('=', 2)
          break unless k
          h[k] = v
        end
        h['source'] = f.read
      }
      h
    end

    def save_properties(rel, h)
      source = h.delete('source')
      atomic_write_open(rel) {|f|
        h.each do |key, val|
          f.puts "#{key}=#{val}"
        end
        f.puts
        f.puts source
      }
    end

    private

    def atomic_write_open(rel, &block)
      tmppath = realpath(rel) + '.writing'
      File.open(tmppath, 'w', &block)
      File.rename tmppath, realpath(rel)
    ensure
      File.unlink tmppath  rescue nil
    end

    def realpath(rel)
      "#{@prefix}/#{rel}"
    end

  end


  class Entry

    def self.persistent_properties
      @slots = []
      yield
      sep = ";"
      module_eval(src = <<-End, __FILE__, __LINE__ + 1)
        def init_properties
          if saved?
            #{@slots.map {|s| "@#{s.name} = nil" }.join(sep)}
            @loaded = false
          else
            clear
          end
        end

        def clear
          #{@slots.map {|s| "@#{s.name} = #{s.initial_value}" }.join(sep)}
          @loaded = true
        end

        def _load_properties(h)
          #{@slots.map {|s| "@#{s.name} = #{s.deserializer}" }.join(sep)}
        end

        def _hashize_properties
          h = {}
          #{@slots.map {|s| "h['#{s.name}'] = #{s.serializer}" }.join(sep)}
          h
        end
      End
      @slots.each do |slot|
        module_eval(<<-End, __FILE__, __LINE__ + 1)
          def #{slot.name}
            @#{slot.name} or
                begin
                  _load_properties @db.load_properties(objpath())
                  @loaded = true
                  @#{slot.name}
                end
          end

          def #{slot.name}=(value)
            unless @loaded
              _load_properties @db.load_properties(objpath())
              @loaded = true
            end
            @#{slot.name} = value
          end
        End
      end
    end

    def self.property(name, type)
      @slots.push Property.new(name, type)
    end

    class Property
      def initialize(name, type)
        @name = name
        @type = type
      end

      attr_reader :name

      def initial_value
        case @type
        when 'String'         then "'(uninitialized)'"
        when 'Symbol'         then ":unknown"
        when 'LibraryEntry'   then ":unknown"
        when 'ClassEntry'     then ":unknown"
        when 'MethodEntry'    then ":unknown"
        when '[String]'       then "[]"
        when '[LibraryEntry]' then "[]"
        when '[ClassEntry]'   then "[]"
        when '[MethodEntry]'  then "[]"
        else
          raise "must not happen: @type=#{@type.inspect}"
        end
      end

      def deserializer
        case @type
        when 'String'         then "h['#{@name}']"
        when 'Symbol'         then "h['#{@name}'].intern"
        when 'LibraryEntry'   then "restore_library(h['#{@name}'])"
        when 'ClassEntry'     then "restore_class(h['#{@name}'])"
        when 'MethodEntry'    then "restore_method(h['#{@name}'])"
        when '[String]'       then "h['#{@name}'].split(',')"
        when '[LibraryEntry]' then "restore_libraries(h['#{@name}'])"
        when '[ClassEntry]'   then "restore_classes(h['#{@name}'])"
        when '[MethodEntry]'  then "restore_methods(h['#{@name}'])"
        else
          raise "must not happen: @type=#{@type.inspect}"
        end
      end

      def serializer
        case @type
        when 'String'         then "@#{@name}"
        when 'Symbol'         then "@#{@name}.to_s"
        when 'LibraryEntry'   then "serialize_entry(@#{@name})"
        when 'ClassEntry'     then "serialize_entry(@#{@name})"
        when 'MethodEntry'    then "serialize_entry(@#{@name})"
        when '[String]'       then "@#{@name}.join(',')"
        when '[LibraryEntry]' then "serialize_entries(@#{@name})"
        when '[ClassEntry]'   then "serialize_entries(@#{@name})"
        when '[MethodEntry]'  then "serialize_entries(@#{@name})"
        else
          raise "must not happen: @type=#{@type.inspect}"
        end
      end
    end

    include NameUtils

    class << self
      alias load new
    end

    def initialize(db)
      @db = db
    end

    def type_id
      self.class.type_id
    end

    def loaded?
      @loaded
    end

    def encoding
      @db.encoding
    end

    attr_writer :source

    def save
      @db.makepath File.dirname(objpath())
      @db.save_properties objpath(), _hashize_properties()
    end

    private

    def saved?
      @db.exist?(objpath())
    end

    def restore_library(id)
      LibraryEntry.load(@db, id)
    end

    def restore_class(id)
      id.empty? ? nil : ClassEntry.load(@db, id)
    end

    def restore_libraries(str)
      restore_entries(str, LibraryEntry)
    end

    def restore_classes(str)
      restore_entries(str, ClassEntry)
    end

    def restore_methods(str)
      restore_entries(str, MethodEntry)
    end

    def restore_entries(str, klass)
      str.split(',').map {|id| klass.load(@db, id) }
    end

    def serialize_Entry(x)
      x ? x.id : ''
    end

    def serialize_entries(xs)
      xs.map {|x| x.id }.join(',')
    end

    def objpath
      "#{type_id()}/#{id()}"
    end

  end


  class LibraryEntry < Entry

    include Enumerable

    def LibraryEntry.type_id
      :library
    end

    def initialize(db, id)
      super db
      @id = id
      if saved?
        @classmap = nil
        @methodmap = nil
      else
        @classmap = {}
        @methodmap = {}
      end
      init_properties
    end

    attr_reader :id

    def name
      libid2name(@id)
    end

    persistent_properties {
      property :requires, '[LibraryEntry]'
      property :classes,  '[ClassEntry]'   # :defined classes
      property :methods,  '[MethodEntry]'  # :added/:redefined entries
      property :source,   'String'
    }

    def inspect
      "#<library #{@id}>"
    end

    def require(lib)
      requires().push lib
    end

    def classnames
      classes().map {|c| c.name }
    end

    def each_class(&block)
      classes().each(&block)
    end

    def classmap
      @classmap ||=
          begin
            h = {}
            classes().each do |c|
              h[c.name] = c
            end
            h
          end
    end
    private :classmap

    def methodnames
      methods().map {|m| m.label }
    end

    def each_method(&block)
      methods().each(&block)
    end

    def methodmap
      @methodmap ||=
          begin
            h = {}
            methods().each do |m|
              h[m] = m
            end
            h
          end
    end
    private :methodmap

    def add_class(c)
      unless classmap()[c.name]
        classes().push c
        classmap()[c.name] = c
        @db.dirty_class self
      end
    end

    def add_method(m)
      unless methodmap()[m]
        methods().push m
        methodmap()[m] = m
        @db.dirty_method self
      end
    end

  end


  # Represents classes, modules and singleton objects.
  class ClassEntry < Entry

    include Enumerable

    def ClassEntry.type_id
      :class
    end

    def initialize(db, id)
      super db
      @id = id
      @entries = saved? ? nil : []
      init_properties
    end

    attr_reader :id

    def name
      classid2name(@id)
    end

    persistent_properties {
      property :type,       'Symbol'         # :class | :module | :object
      property :superclass, 'ClassEntry'
      property :included,   '[ClassEntry]'
      property :extended,   '[ClassEntry]'
      property :library,    'LibraryEntry'
      property :source,     'String'
    }

    def entries
      @entries ||= @db.entries("method/#{id()}")\
          .map {|ent| MethodEntry.new(@db, "#{id()}/#{ent}") }
    end

    def inspect
      "\#<#{type()} #{@id}>"
    end

    def class?
      type() == :class
    end

    def module?
      type() == :module
    end

    def object?
      type() == :object
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

  end


  # Represents methods, constants, and special variables.
  class MethodEntry < Entry

    def MethodEntry.type_id
      :method
    end

    def initialize(db, id)
      super db
      @id = id
      init_properties
    end

    attr_reader :id

    def name
      methodid2mname(@id)
    end

    persistent_properties {
      property :names,      '[String]'
      property :library,    'LibraryEntry'
      property :klass,      'ClassEntry'
      property :type,       'Symbol'   # :singleton_method | :instance_method
                                       #     | :module_function | :constant
                                       #     | :special_variable
      property :visibility, 'Symbol'   # :public | :private | :protected
      property :kind,       'Symbol'   # :defined | :added | :redefined
      property :source,     'String'
    }

    def inspect
      "\#<method #{klass().name}#{typemark()}#{names().join(',')}>"
    end

    def label
      "#{klass().name}#{typemark()}#{name()}"
    end

    def typemark
      typename2mark(type())
    end

    def singleton_method?
      t = type()
      t == :singleton_method or t == :module_function
    end

    def instance_method?
      t = type()
      t == :instance_method or t == :module_function
    end

    def constant?
      type() == :constant
    end

    def special_variable?
      type() == :special_variable
    end

  end

end

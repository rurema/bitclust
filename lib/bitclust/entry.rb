#
# bitclust/entry.rb
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

  class Entry

    include NameUtils

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

        def _set_properties(h)
          #{@slots.map {|s| "@#{s.name} = #{s.deserializer}" }.join(sep)}
        end

        def _get_properties
          h = {}
          #{@slots.map {|s| "h['#{s.name}'] = #{s.serializer}" }.join(sep)}
          h
        end
      End
      @slots.each do |slot|
        module_eval(<<-End, __FILE__, __LINE__ + 1)
          def #{slot.name}
            load unless @loaded
            @#{slot.name}
          end

          def #{slot.name}=(value)
            load unless @loaded
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
        when 'Symbol'         then "nil"
        when 'LibraryEntry'   then "nil"
        when 'ClassEntry'     then "nil"
        when 'MethodEntry'    then "nil"
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

    def synopsis_source
      source().split(/\n\n/, 2).first
    end

    def save
      @db.makepath File.dirname(objpath())
      @db.save_properties objpath(), _get_properties()
    end

    private

    def load
      _set_properties @db.load_properties(objpath())
      @loaded = true
    end

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

    def serialize_entry(x)
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

    def ==(other)
      @id == other.id
    end

    alias eql? ==

    def hash
      @id.hash
    end

    def <=>(other)
      @id <=> other.id
    end

    def name
      libid2name(@id)
    end

    def name?(n)
      name() == n
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

    def fetch_class(name)
      classes().detect {|c| c.name == name } or
          raise ClassNotFound, "no such class in the library #{name()}: #{name}"
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

    def fetch_method(spec)
      classes().each do |c|
        m = c.get_method(spec)
        return m if m
      end
      methods().detect {|m| spec.match?(m) } or
        raise MethodNotFound, "no such method in the library #{name()}: #{name}"
    end

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
        @db.dirty_library self
      end
    end

    def add_method(m)
      unless methodmap()[m]
        methods().push m
        methodmap()[m] = m
        @db.dirty_library self
      end
    end

  end


  # Represents a class, a module and a singleton object.
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

    def ==(other)
      @id == other.id
    end

    alias eql? ==

    def hash
      @id.hash
    end

    def <=>(other)
      @id <=> other.id
    end

    def name
      classid2name(@id)
    end

    def name?(n)
      name() == n
    end

    def name_match?(re)
      re =~ name()
    end

    alias label name

    # FIXME: implement class alias
    def labels
      [label()]
    end

    persistent_properties {
      property :type,       'Symbol'         # :class | :module | :object
      property :superclass, 'ClassEntry'
      property :included,   '[ClassEntry]'
      property :extended,   '[ClassEntry]'
      property :library,    'LibraryEntry'
      property :source,     'String'
    }

    def clear_cache
      @smap = @imap = @cmap = nil
    end

    def save
      super
      @db.atomic_write_open("method/#{@id}/=smap") {|f|
        write_mmap smap(), f
      }
      @db.atomic_write_open("method/#{@id}/=imap") {|f|
        write_mmap imap(), f
      }
      @db.atomic_write_open("method/#{@id}/=cmap") {|f|
        write_mmap cmap(), f
      }
    end

    def load
      super
      @smap = parse_mmap(@db.read("method/#{@id}/=smap"))
      @imap = parse_mmap(@db.read("method/#{@id}/=imap"))
      @cmap = parse_mmap(@db.read("method/#{@id}/=cmap"))
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

    def ancestors
      @ancestors ||=
          [ self, included().map {|m| m.ancestors },
            superclass() ? superclass().ancestors : [] ].flatten
    end

    def included_modules
      list = ancestors().select {|c| c.module? }
      list.delete self
      list
    end

    def extended_modules
      ancestors().select {|c| c.class? }.map {|c| c.extended }.flatten
    end

    def entries
      @entries ||= @db.entries("method/#{@id}")\
          .reject {|ent| /\A=/ =~ ent }\
          .map {|ent| MethodEntry.new(@db, "#{@id}/#{ent}") }
    end

    alias methods entries

    def each(&block)
      entries().each(&block)
    end

    def add_method(m)
      # FIXME: check duplication?
      entries().push m
    end

    Parts = Struct.new(:singleton_methods, :private_singleton_methods,
                       :instance_methods,  :private_instance_methods,
                       :module_functions,
                       :constants, :special_variables)

    def partitioned_entries
      s = []; spv = []
      i = []; ipv = []
      mf = []
      c = []; v = []
      entries().each do |m|
        case m.type
        when :singleton_method
          (m.public? ? s : spv).push m
        when :instance_method
          (m.public? ? i : ipv).push m
        when :module_function
          mf.push m
        when :constant
          c.push m
        when :special_variable
          v.push m
        else
          raise "must not happen: m.type=#{m.type.inspect} (#{m.inspect})"
        end
      end
      Parts.new(*[s,spv, i,ipv, mf, c, v].map {|ents| ents.sort })
    end

    def singleton_methods(inherit = true)
      # FIXME: inheritance
      entries().select {|m| m.singleton_method? }.sort
    end

    def public_singleton_methods(inherit = true)
      # FIXME: inheritance
      entries().select {|m| m.public_singleton_method? }.sort
    end

    def instance_methods(inherit = true)
      # FIXME: inheritance
      entries().select {|m| m.instance_method? }.sort
    end

    def private_singleton_methods(inherit = true)
      # FIXME: inheritance
      entries().select {|m| m.private_singleton_method? }.sort
    end

    def public_instance_methods(inherit = true)
      # FIXME: inheritance
      entries().select {|m| m.public_instance_method? }.sort
    end

    def private_instance_methods(inherit = true)
      # FIXME: inheritance
      entries().select {|m| m.private_instance_method? }.sort
    end

    alias private_methods   private_instance_methods

    def constants(inherit = true)
      entries().select {|m| m.constant? }.sort
    end

    def special_variables
      entries().select {|m| m.special_variable? }.sort
    end

    def singleton_method?(name, inherit = true)
      if inherit
        smap().key?(name)
      else
        singleton_methods(false).detect {|m| m.name?(name) }
      end
    end

    def instance_method?(name, inherit = true)
      if inherit
        imap().key?(name)
      else
        instance_methods(false).detect {|m| m.name?(name) }
      end
    end

    def constant?(name, inherit = true)
      if inherit
        ancestors().any? {|c| c.constant?(name, false) }
      else
        constants(false).detect {|m| m.name?(name) }
      end
    end

    def special_variable?(name)
      special_variables().detect {|m| m.name?(name) }
    end

    def get_method(spec)
      entries().detect {|m| spec.match?(m) }
    end

    def fetch_method(spec)
      get_method(spec) or
          raise MethodNotFound, "spec=#{spec.inspect}"
    end

    def singleton_method_names
      # should remove module functions?
      smap().keys
    end

    def instance_method_names
      imap().keys
    end

    def constant_names
      cmap().keys
    end

    def special_variable_names
      special_variables().map {|m| m.names }.flatten
    end

    # internal use only
    def smap
      @smap ||= makemmap('s', extended_modules(), singleton_methods())
    end

    # internal use only
    def imap
      @imap ||= makemmap('i', included_modules(), instance_methods())
    end

    # internal use only
    def cmap
      @cmap ||= makemmap('c', included_modules(), constants())
    end

    private

    def makemmap(typechar, inherited_modules, ents)
      s = superclass()
      map = s ? s.__send("#{typechar}map").dup : {}
      if typechar == 'c'
        inherited_modules.each do |mod|
          map.update mod.cmap
        end
      else
        inherited_modules.each do |mod|
          map.update mod.imap
        end
      end
      defined, undefined = *ents.partition {|m| m.defined? }
      (undefined + defined).each do |m|
        m.names.each do |name|
          map[name] = m.spec
        end
      end
      map
    end

    def write_mmap(map, f)
      map.to_a.sort_by {|k,v| k }.each do |name, m|
        f.puts "#{name}\t#{m}"
      end
    end

    def parse_mmap(str)
      map = {}
      str.each_line do |line|
        name, spec = *line.split
        map[name] = spec
      end
      map
    end

  end


  # Represents a method, a constant, and a special variable.
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

    def ==(other)
      @id == other.id
    end

    alias eql? ==

    def hash
      @id.hash
    end

    def <=>(other)
      @id <=> other.id
    end

    def name
      methodid2mname(@id)
    end

    # typename = :singleton_method
    #          | :instance_method
    #          | :module_function
    #          | :constant
    #          | :special_variable
    def typename
      methodid2typename(@id)
    end

    alias type typename

    def typemark
      typename2mark(typename())
    end

    def typechar
      typename2char(typename())
    end

    def library
      @library ||= @db.fetch_library_id(methodid2libid(@id))
    end

    attr_writer :library

    def klass
      @klass ||= @db.fetch_class_id(methodid2classid(@id))
    end

    attr_writer :klass

    persistent_properties {
      property :names,      '[String]'
      property :visibility, 'Symbol'   # :public | :private | :protected
      property :kind,       'Symbol'   # :defined | :added | :redefined
      property :source,     'String'
    }

    def inspect
      "\#<method #{klass().name}#{typemark()}#{names().join(',')}>"
    end

    def spec
      "#{klass().name}#{typemark()}#{name()}"
    end

    alias label spec

    def labels
      names().map {|name| "#{klass().name}#{typemark()}#{name}" }
    end

    def name?(name)
      names().include?(name)
    end

    def name_match?(re)
      names().any? {|n| re =~ n }
    end

    def really_public?
      visibility() == :public
    end

    def public?
      visibility() != :private
    end

    def protected?
      visibility() == :protected
    end

    def private?
      visibility() == :private
    end

    def public_singleton_method?
      singleton_method? and public?
    end

    def private_singleton_method?
      singleton_method? and private?
    end

    def public_instance_method?
      instance_method? and public?
    end

    def private_instance_method?
      instance_method? and public?
    end

    def singleton_method?
      t = typename()
      t == :singleton_method or t == :module_function
    end

    def instance_method?
      t = typename()
      t == :instance_method or t == :module_function
    end

    def constant?
      typename() == :constant
    end

    def special_variable?
      typename() == :special_variable
    end

    def defined?
      kind() == :defined
    end

    def added?
      kind() == :added
    end

    def redefined?
      kind() == :redefined
    end

  end

end

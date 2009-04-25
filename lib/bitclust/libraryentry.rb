#
# bitclust/libraryentry.rb
#
# Copyright (c) 2006-2008 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

require 'bitclust/entry'
require 'bitclust/exception'

module BitClust

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
        @link_checked = true
      else
        @classmap = {}
        @methodmap = {}
        @link_checked = false
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
      @id.casecmp(other.id)
    end

    def name
      libid2name(@id)
    end
    alias label name

    def labels
      [label()]
    end
    
    def name?(n)
      name() == n
    end

    persistent_properties {
      property :requires, '[LibraryEntry]'
      property :classes,  '[ClassEntry]'   # :defined classes
      property :methods,  '[MethodEntry]'  # :added/:redefined entries
      property :source,   'String'
      property :sublibraries, '[LibraryEntry]'
      property :is_sublibrary,   'bool'
    }

    def inspect
      "#<library #{@id}>"
    end

    def check_link(path = [])
      return if @link_checked
      if path.include?(name())
        raise InvalidLink, "looped require: #{path_string(path)}"
      end
      path.push name()
      requires().each do |lib|
        lib.check_link path
      end
      path.pop
      @link_checked = true
    end

    def all_requires(libs = {})
      requires.each{|l|
        next if libs[l.name] 
        libs[l.name] = l
        l.all_requires(libs)
      }
      libs.values
    end

    def all_classes
      return @all_classes if @all_classes
      required_classes = (sublibraries & requires).map{|l| l.classes }.flatten
      @all_classes = (classes() + required_classes).uniq.sort
    end
    
    def error_classes
      @error_classes ||= classes.select{|c| c.ancestors.any?{|k| k.name == 'Exception' }}
    end

    def all_error_classes
      @all_error_classes ||= all_classes.select{|c| c.ancestors.any?{|k| k.name == 'Exception' }}
    end
    
    def require(lib)
      requires().push lib
    end

    def sublibrary(lib)
      sublibraries().push lib
      lib.is_sublibrary = true
    end
    
    def fetch_class(name)
      get_class(name) or
          raise ClassNotFound, "no such class in the library #{name()}: #{name}"
    end

    def get_class(name)
      classes().detect {|c| c.name == name }
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

    def fetch_methods(spec)
      ms = if c = get_class(spec.klass)
           then c.fetch_methods(spec)
           else []
           end +
           methods().select {|m| spec.match?(m) }
      if ms.empty?
        raise MethodNotFound, "no such method in the library #{name()}: #{name}"
      end
      ms
    end

    def fetch_method(spec)
      classes().each do |c|
        m = c.get_method(spec)
        return m if m
      end
      methods().detect {|m| spec.match?(m) } or
        raise MethodNotFound, "no such method in the library #{name()}: #{name}"
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

end

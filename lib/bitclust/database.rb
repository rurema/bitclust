#
# bitclust/database.rb
#
# Copyright (c) 2006 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

require 'bitclust/entry'
require 'bitclust/methodnamepattern'
require 'bitclust/nameutils'
require 'bitclust/exception'
require 'fileutils'

module BitClust

  class Database

    include NameUtils

    def Database.dummy
      new(nil)
    end

    def Database.datadir?(dir)
      File.file?("#{dir}/properties")
    end

    def initialize(prefix)
      @prefix = prefix
      @properties = nil
      @librarymap = nil
      @classmap = nil
      @in_transaction = false
      @properties_dirty = false
      @dirty_libraries = {}
      @dirty_classes = {}
      @dirty_methods = {}
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
      if dirty?
        each_dirty_library do |lib|
          lib.check_link
        end
        each_dirty_class do |c|
          c.clear_cache
          c.check_ancestor_type
        end
        each_dirty_class do |c|
          c.check_ancestors_link
        end
        each_dirty_entry do |x|
          x.save
        end
        clear_dirty
        save_method_index
      end
    ensure
      @in_transaction = false
    end

    def check_transaction
      return if dummy?
      unless @in_transaction
        raise NotInTransaction, "database changed without transaction"
      end
    end
    private :check_transaction

    def dirty?
      not @dirty_libraries.empty? or
      not @dirty_classes.empty? or
      not @dirty_methods.empty?
    end

    def each_dirty_entry(&block)
      (@dirty_libraries.keys +
       @dirty_classes.keys +
       @dirty_methods.keys).each(&block)
    end

    def dirty_library(lib)
      @dirty_libraries[lib] = true
    end

    def each_dirty_library(&block)
      @dirty_libraries.each_key(&block)
    end

    def dirty_class(c)
      @dirty_classes[c] = true
    end

    def each_dirty_class(&block)
      @dirty_classes.each_key(&block)
    end

    def dirty_method(m)
      @dirty_methods[m] = true
    end

    def each_dirty_method(&block)
      @dirty_methods.each_key(&block)
    end

    def clear_dirty
      @dirty_libraries.clear
      @dirty_classes.clear
      @dirty_methods.clear
    end

    def update_by_stdlibtree(root)
      parse_LIBRARIES("#{root}/LIBRARIES", properties()).each do |libname|
        update_by_file "#{root}/#{libname}.rd", libname
      end
    end

    def parse_LIBRARIES(path, properties)
      File.open(path) {|f|
        BitClust::Preprocessor.wrap(f, properties).map {|line| line.strip }
      }
    end
    private :parse_LIBRARIES

    def update_by_file(path, libname)
      check_transaction
      RRDParser.new(self).parse_file(path, libname, properties())
    end

    #
    # Properties
    #

    def properties
      @properties ||=
          begin
            h = load_properties('properties')
            h.delete 'source' if h['source'] and h['source'].strip.empty?
            h
          end
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

    #
    # Library Entry
    #

    def libraries
      librarymap().values
    end

    def librarymap
      @librarymap ||= load_extent(LibraryEntry)
    end
    private :librarymap

    def get_library(name)
      id = libname2id(name)
      librarymap()[id] ||= LibraryEntry.new(self, id)
    end

    def fetch_library(name)
      librarymap()[libname2id(name)] or
          raise LibraryNotFound, "library not found: #{name.inspect}"
    end

    def fetch_library_id(id)
      librarymap()[id] or
          raise LibraryNotFound, "library not found: #{id.inspect}"
    end

    def open_library(name, reopen = false)
      check_transaction
      map = librarymap()
      id = libname2id(name)
      if lib = map[id]
        lib.clear unless reopen
      else
        map[id] = lib = LibraryEntry.new(self, id)
      end
      dirty_library lib
      lib
    end

    #
    # Classe Entry
    #

    def classes
      classmap().values
    end

    def classmap
      @classmap ||= load_extent(ClassEntry)
    end
    private :classmap

    def get_class(name)
      id = classname2id(name)
      classmap()[id] ||= ClassEntry.new(self, id)
    end

    def fetch_class(name)
      classmap()[classname2id(name)] or
          raise ClassNotFound, "class not found: #{name.inspect}"
    end

    def fetch_class_id(id)
      classmap()[id] or
          raise ClassNotFound, "class not found: #{id.inspect}"
    end

    def search_classes(pattern)
      cs = MethodNamePattern.new(pattern, nil, nil).select_classes(classes())
      if cs.empty?
        raise ClassNotFound, "no such class: #{pattern}"
      end
      cs
    end

    def open_class(name)
      check_transaction
      map = classmap()
      id = classname2id(name)
      if c = map[id]
        c.clear
      else
        map[id] = c = ClassEntry.new(self, id)
      end
      yield c
      dirty_class c
      c
    end

    def load_extent(entry_class)
      h = {}
      entries(entry_class.type_id.to_s).each do |id|
        h[id] = entry_class.new(self, id)
      end
      h
    end
    private :load_extent

    #
    # Method Entry
    #

    # FIXME: see kind
    def open_method(id)
      check_transaction
      if m = id.klass.get_method(id)
        m.clear
      else
        m = MethodEntry.new(self, id.idstring)
        id.klass.add_method m
      end
      m.library = id.library
      m.klass   = id.klass
      yield m
      dirty_method m
      m
    end

    def methods
      classes().map {|c| c.entries }.flatten
    end

    def get_method(spec)
      get_class(spec.klass).get_method(spec)
    end

    def fetch_method(spec)
      fetch_class(spec.klass).fetch_method(spec)
    end

    def search_method(pattern)
      search_methods(pattern).first
    end

    def search_methods(pattern)
      result = pattern._search_methods(self)
      if result.fail?
        if result.classes.empty?
          raise MethodNotFound, "no such class: #{pattern.klass}"
        end
        if result.classes.size <= 5
          loc = result.classes.map {|c| c.label }.join(', ')
        else
          loc = "#{result.classes.size} classes"
        end
        raise MethodNotFound, "no such method in #{loc}: #{pattern.method}"
      end
      result
    end

    def save_method_index
      atomic_write_open('method/=mindex') {|f|
        h = make_method_index()
        h.keys.sort.each do |name|
          f.puts "#{name}\t#{h[name].map {|c| c.id }.uniq.join(' ')}"
        end
      }
    end
    private :save_method_index

    def make_method_index
      h = {}
      classes().each do |c|
        c.entries.each do |m|
          m.names.each do |name|
            (h[name] ||= []).push c
          end
        end
      end
      libraries().each do |lib|
        lib.methods.each do |m|
          m.names.each do |name|
            (h[name] ||= []).push m.klass
          end
        end
      end
      h
    end
    private :make_method_index

    # internal use only
    def _method_index
      @method_index ||=
          begin
            h = {}
            cmap = classmap()
            foreach_line('method/=mindex') do |line|
              name, *cids = *line.split
              h[name] = cids.map {|cid| cmap[cid] }
            end
            h
          end
    end

    #
    # Direct File Access (Internal use only)
    #

    def exist?(rel)
      return false unless @prefix
      File.exist?(realpath(rel))
    end

    def entries(rel)
      Dir.entries(realpath(rel))\
          .reject {|ent| /\A[\.=]/ =~ ent }\
          .map {|ent| decodeid(ent) }
    rescue Errno::ENOENT
      return []
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
    rescue Errno::ENOENT
      return {}
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

    def read(rel)
      File.read(realpath(rel))
    end

    def foreach_line(rel, &block)
      File.foreach(realpath(rel), &block)
    end

    def atomic_write_open(rel, &block)
      FileUtils.mkdir_p File.dirname(realpath(rel))
      tmppath = realpath(rel) + '.writing'
      File.open(tmppath, 'w', &block)
      File.rename tmppath, realpath(rel)
    ensure
      File.unlink tmppath  rescue nil
    end

    private

    def realpath(rel)
      "#{@prefix}/#{encodeid(rel)}"
    end

  end

end

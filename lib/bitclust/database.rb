#
# bitclust/database.rb
#
# Copyright (c) 2006-2007 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

require 'bitclust/entry'
require 'bitclust/completion'
require 'bitclust/refsdatabase'
require 'bitclust/rrdparser'
require 'bitclust/functionreferenceparser'
require 'bitclust/nameutils'
require 'bitclust/exception'
require 'fileutils'

module BitClust

  class Database

    include Completion
    include NameUtils

    def Database.datadir?(dir)
      File.file?("#{dir}/properties")
    end

    def Database.connect(uri)
      case uri.scheme
      when 'file'
        new(uri.path)
      when 'druby'
        DRbObject.new_with_uri(uri.to_s)
      else
        raise InvalidScheme, "unknown database scheme: #{uri.scheme}"
      end
    end

    def Database.dummy(params = {})
      db = new(nil)
      db.properties['version'] = params['version']
      db.refs = RefsDatabase.new
      db
    end

    def initialize(prefix)
      @prefix = prefix
      @properties = nil
      @librarymap = nil
      @classmap = {}
      @class_extent_loaded = false
      @in_transaction = false
      @properties_dirty = false
      @dirty_libraries = {}
      @dirty_classes = {}
      @dirty_methods = {}
    end
    attr_writer :refs
    
    def dummy?
      not @prefix
    end

    def init
      FileUtils.rm_rf @prefix
      FileUtils.mkdir_p @prefix
      Dir.mkdir "#{@prefix}/library"
      Dir.mkdir "#{@prefix}/class"
      Dir.mkdir "#{@prefix}/method"
      Dir.mkdir "#{@prefix}/doc"
      FileUtils.touch "#{@prefix}/properties"
      FileUtils.touch "#{@prefix}/refs"
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
        update_requires()
        update_sublibraries()
        # FIXME: many require loops in tk
        #each_dirty_library do |lib|
        #  lib.check_link
        #end
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
        save_completion_index
        copy_doc
        make_refs
        refs().save(realpath('refs'))
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

    def update_requires
      libraries.each{|lib|
        lib.requires = lib.all_requires
      }
    end
    
    def update_sublibraries
      libraries.each{|lib|
        re = /\A#{lib.name}\// 
        libraries.each{|l|
          lib.sublibrary(l) if re =~ l.name
        }
      }
    end
    
    def update_by_stdlibtree(root)
      @root = root
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
    
    def refs
      @refs ||= RefsDatabase.load( realpath('refs') )
    end

    def make_refs
      [classes, libraries, methods, docs].each{|es|        
        es.each{|e|
          refs().extract(e)
        }
      }
      refs
    end
    
    def copy_doc
      Dir.glob("#{@root}/../../doc/**/*.rd").each{|f|          
        if %r!\A#{Regexp.escape(@root)}/\.\./\.\./doc/([-\./\w]+)\.rd\z! =~ f            
          id = libname2id($1)
          se = DocEntry.new(self, id)
          se.source = Preprocessor.read(f, properties)
          se.title = RRDParser.title(se.source) || ""
          se.save
        end
      }
    end

    #
    # Doc Entry
    #
    
    def docs
      docmap().values
    end

    def docmap
      @docmap ||= load_extent(DocEntry)
    end
    private :docmap

    def get_doc(name)
      id = libname2id(name)
      docmap()[id] ||= DocEntry.new(self, id)
    end

    def fetch_doc(name)
      docmap()[libname2id(name)] or
          raise DocNotFound, "doc not found: #{name.inspect}"
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
        lib = (map[id] ||= LibraryEntry.new(self, id))
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
      return @classmap if @class_extent_loaded
      id_extent(ClassEntry).each do |id|
        @classmap[id] ||= ClassEntry.new(self, id)
      end
      @class_extent_loaded = true
      @classmap
    end
    private :classmap

    def get_class(name)
      if id = intern_classname(name)
        load_class(id) or
            raise "must not happen: #{name.inspect}, #{id.inspect}"
      else
        id = classname2id(name)
        @classmap[id] ||= ClassEntry.new(self, id)
      end
    end

    # This method does not work in transaction.
    def fetch_class(name)
      id = intern_classname(name) or
          raise ClassNotFound, "class not found: #{name.inspect}"
      load_class(id) or
          raise "must not happen: #{name.inspect}, #{id.inspect}"
    end

    def fetch_class_id(id)
      load_class(id) or
          raise ClassNotFound, "class not found: #{id.inspect}"
    end

    def search_classes(pattern)
      cs = _search_classes(pattern)
      if cs.empty?
        raise ClassNotFound, "no such class: #{pattern}"
      end
      cs
    end

    def open_class(name)
      check_transaction
      id = classname2id(name)
      if exist?("class/#{id}")
        c = load_class(id)
        c.clear
      else
        c = (@classmap[id] ||= ClassEntry.new(self, id))
      end
      yield c
      dirty_class c
      c
    end

    def load_class(id)
      @classmap[id] ||=
          begin
            return nil unless exist?("class/#{id}")
            ClassEntry.new(self, id)
          end
    end
    private :load_class

    def load_extent(entry_class)
      h = {}
      id_extent(entry_class).each do |id|
        h[id] = entry_class.new(self, id)
      end
      h
    end
    private :load_extent

    def id_extent(entry_class)
      entries(entry_class.type_id.to_s)
    end
    private :id_extent

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

    def fetch_methods(spec)
      fetch_class(spec.klass).fetch_methods(spec)
    end

    def fetch_method(spec)
      fetch_class(spec.klass).fetch_method(spec)
    end

    def search_method(pattern)
      search_methods(pattern).first
    end

    def search_methods(pattern)
      result = _search_methods(pattern)
      if result.fail?
        if result.classes.size <= 5
          loc = result.classes.map {|c| c.label }.join(', ')
        else
          loc = "#{result.classes.size} classes"
        end
        raise MethodNotFound, "no such method in #{loc}: #{pattern.method}"
      end
      result
    end

  end


  # internal use only
  module DirectFileAccess

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
      tmppath = realpath(rel) + '.writing'
      File.open(tmppath, 'wb', &block)
      File.rename tmppath, realpath(rel)
    ensure
      File.unlink tmppath  rescue nil
    end

    def realpath(rel)
      "#{@prefix}/#{encodeid(rel)}"
    end
    private :realpath

  end


  class Database   # reopen
    include DirectFileAccess
  end


  class FunctionDatabase

    include DirectFileAccess
    include NameUtils

    def initialize(prefix)
      @prefix = prefix
      @properties = nil
      @in_transaction = false
      @properties_dirty = false
      @dirty_functions = {}
      @functionmap = {}
      @function_extent_loaded = false
    end

    attr_reader :properties

    def encoding
      'euc-jp'
    end

    def transaction
      @in_transaction = true
      yield
      return if dummy?
      if @properties_dirty
        save_properties 'properties', @properties
        @properties_dirty = false
      end
      if dirty?
        each_dirty_function do |f|
          f.save
        end
        clear_dirty
#        save_completion_index
      end
    ensure
      @in_transaction = false
    end

    def dummy?
      not @prefix
    end

    def dirty_function(f)
      @dirty_functions[f] = true
    end

    def dirty?
      not @dirty_functions.empty?
    end

    def each_dirty_function(&block)
      @dirty_functions.each_key(&block)
    end

    def clear_dirty
      @dirty_functions.clear
    end

    def check_transaction
      return if dummy?
      unless @in_transaction
        raise NotInTransaction, "begin transaction before changing DB"
      end
    end
    private :check_transaction

    def update_by_file(path, filename)
      check_transaction
      FunctionReferenceParser.new(self).parse_file(path, filename, properties())
    end

    def open_function(id)
      check_transaction
      if exist?("function/#{id}")
        f = load_function(id)
        f.clear
      else
        f = (@functionmap[id] ||= FunctionEntry.new(self, id))
      end
      yield f
      dirty_function f
      f
    end

    def fetch_function(id)
      load_function(id) or
          raise FunctionNotFound, "function not found: #{id.inspect}"
    end

    def load_function(id)
      @functionmap[id] ||=
          begin
            return nil unless exist?("function/#{id}")
            FunctionEntry.new(self, id)
          end
    end
    private :load_function

    def functions
      functionmap().values
    end

    def functionmap
      return @functionmap if @function_extent_loaded
      id_extent(FunctionEntry).each do |id|
        @functionmap[id] ||= FunctionEntry.new(self, id)
      end
      @function_extent_loaded = true
      @functionmap
    end
    private :functionmap

    def id_extent(entry_class)
      entries(entry_class.type_id.to_s)
    end
    private :id_extent

  end

end

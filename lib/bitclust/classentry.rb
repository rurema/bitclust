#
# bitclust/classentry.rb
#
# Copyright (c) 2006-2008 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

require 'bitclust/entry'
require 'bitclust/exception'

module BitClust

  # Represents a class, a module and a singleton object.
  class ClassEntry < Entry

    include Enumerable

    def ClassEntry.type_id
      :class
    end

    def initialize(db, id)
      super db
      @id = id
      if saved?
        @entries = nil
        @ancestors_checked = true
        @s_ancestors_checked = true
      else
        @entries = []
        @ancestors_checked = false
        @s_ancestors_checked = false
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

    def save
      super
      save_index
    end

    def inspect
      "\#<#{type()} #{@id}>"
    end

    def dummy?
      not type()
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

    def check_ancestor_type
      s = superclass()
      if s and not s.class? and not s.dummy?
        raise InvalidAncestor, "#{name()} inherits #{s.name} but it is a #{s.type} (class expected)"
      end
      included().each do |c|
        unless c.module? or c.dummy?
          raise InvalidAncestor, "#{name()} includes #{c.name} but it is a #{c.type} (module expected)"
        end
      end
      extended().each do |c|
        unless c.module? or c.dummy?
          raise InvalidAncestor, "#{name()} extends #{c.name} but it is a #{c.type} (module expected)"
        end
      end
    end

    def check_ancestors_link(path = [])
      return if @ancestors_checked
      if path.include?(name())
        raise InvalidLink, "ancestor link looped: #{path_string(path)}"
      end
      ([superclass()] + included()).compact.each do |c|
        path.push name()
        c.check_ancestors_link path
        path.pop
      end
      @ancestors_checked = true
    end

    def check_singleton_ancestors_link(path = [])
      return if @s_ancestors_checked
      extended().each do |c|
        path.push name()
        c.check_singleton_ancestors_link path
        path.pop
      end
      @s_ancestors_checked = true
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

    def entries(level = 0)
      @entries ||= @db.entries("method/#{@id}")\
          .map {|ent| MethodEntry.new(@db, "#{@id}/#{ent}") }
      ret = @entries
      ancestors[1..level].each{|c| ret += c.entries }
      ret 
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
                       :constants, :special_variables,
                       :added)

    def partitioned_entries(level = 0)
      s = []; spv = []
      i = []; ipv = []
      mf = []
      c = []; v = []
      added = []
      entries(level).sort_by{|e| e.name}.each do |m|
        case m.kind
        when :defined, :redefined
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
        when :added
          added.push m
        end
      end
      Parts.new(s,spv, i,ipv, mf, c, v, added)
    end

    def singleton_methods(level = 0)
      # FIXME: inheritance
      entries(level).select {|m| m.singleton_method? }.sort
    end

    def public_singleton_methods(level = 0)
      # FIXME: inheritance
      entries(level).select {|m| m.public_singleton_method? }.sort
    end

    def instance_methods(level = 0)
      # FIXME: inheritance
      entries(level).select {|m| m.instance_method? }.sort
    end

    def private_singleton_methods(level = 0)
      # FIXME: inheritance
      entries(level).select {|m| m.private_singleton_method? }.sort
    end

    def public_instance_methods(level = 0)
      # FIXME: inheritance
      entries(level).select {|m| m.public_instance_method? }.sort
    end

    def private_instance_methods(level = 0)
      # FIXME: inheritance
      entries(level).select {|m| m.private_instance_method? }.sort
    end

    alias private_methods   private_instance_methods

    def constants(level = 0)
      entries(level).select {|m| m.constant? }.sort
    end

    def special_variables
      entries().select {|m| m.special_variable? }.sort
    end

    def singleton_method?(name, inherit = true)
      if inherit
        _smap().key?(name)
      else
        singleton_methods(false).detect {|m| m.name?(name) }
      end
    end

    def instance_method?(name, inherit = true)
      if inherit
        _imap().key?(name)
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

    def get_methods(spec)
      entries().select {|m| spec.match?(m) }
    end

    def get_method(spec)
      entries().detect {|m| spec.match?(m) }
    end

    def fetch_methods(spec)
      get_methods(spec) or
          raise MethodNotFound, "no such method: #{spec}"
    end

    def fetch_method(spec)
      get_method(spec) or
          raise MethodNotFound, "no such method: #{spec}"
    end

    # internal use only
    def match_entry(t, mname)
      _index()[t + mname]
    end

    def singleton_method_names
      # should remove module functions?
      _index().keys.select {|name| /\A\./ =~ name }.map {|name| name[1..-1] }
    end

    def instance_method_names
      _index().keys.select {|name| /\A\#/ =~ name }.map {|name| name[1..-1] }
    end

    def constant_names
      _index().keys.select {|name| /\A\:/ =~ name }.map {|name| name[1..-1] }
    end

    def special_variable_names
      special_variables().map {|m| m.names }.flatten
    end

    def inherited_method_specs
      cname = name()
      _index().map {|mname, specstr| MethodSpec.parse(specstr) }\
          .reject {|spec| spec.klass == cname }.uniq
    end

    def clear_cache
      @_smap = @_imap = @_cmap = nil
    end

    # internal use only
    def _smap
      @_smap ||= makemap('s', extended_modules(), singleton_methods())
    end

    # internal use only
    def _imap
      @_imap ||= makemap('i', included_modules(), instance_methods())
    end

    # internal use only
    def _cmap
      @_cmap ||= makemap('c', included_modules(), constants())
    end

    private

    def makemap(typechar, inherited_modules, ents)
      s = superclass()
      map = s ? s.__send__("_#{typechar}map").dup : {}
      inherited_modules.each do |mod|
        map.update mod.__send__("_#{typechar == 'c' ? 'c' : 'i'}map")
      end
      defined, undefined = *ents.partition {|m| m.defined? }
      (undefined + defined).each do |m|
        m.names.each do |name|
          map[name] = m.spec_string
        end
      end
      map
    end

    def save_index
      @db.makepath "method/#{@id}"
      @db.atomic_write_open("method/#{@id}/=index") {|f|
        writemap _smap(), '.', f
        writemap _imap(), '#', f
        writemap _cmap(), ':', f
      }
    end

    def writemap(map, mark, f)
      map.to_a.sort_by {|k,v| k }.each do |name, m|
        f.puts "#{mark}#{name}\t#{m}"
      end
    end

    def _index
      @_index ||=
          begin
            h = {}
            @db.foreach_line("method/#{@id}/=index") do |line|
              name, spec = line.split
              h[name] = spec
            end
            h
          end
    end

  end

end

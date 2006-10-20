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

    def initialize(c = nil, t = nil, m = nil, library = nil)
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

    def match?(m)
      m.typemark == @type and m.name?(@method)
    end

  end


  # A SearchPattern has #klass, #type, #method and #library.
  # All attributes are string.
  # All attributes are optional.
  class SearchPattern

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
    private :esc

    def match?(m)
      (not @library or m.library.name?(@library)) and
      (not @klass   or m.klass.name?(@klass)) and
      (not @type    or m.typemark == @type) and
      (not @method  or m.name?(@method))
    end

    def search_methods(db)
      if @type == '$'
        return search_svars(db.fetch_class('Kernel'))
      end
      cs = select_classes(db.classes)
      if cs.empty?
        raise ClassNotFound, "no such class: #{@klass}"
      end
      if @method and /\A[A-Z]/ =~ @method   # seems constant
        records = cs.map {|c| search_methods_in(c, '::') }.flatten
        if records.empty?
          records = cs.map {|c| search_methods_in(c, nil) }.flatten
        end
      else
        records = cs.map {|c| search_methods_in(c, @type) }.flatten
      end
      objectify(db, cs, unify(records))
    end

    def select_classes(cs)
      return cs unless @klass
      completion_search(cs, @klass, @crecache)
    end

    private

    def search_svars(c)
      completion_search(c.special_variables, @method, @mrecache)
    end

    def completion_search(xs, pattern, cache)
      re1 = (cache[0] ||= /\A#{Regexp.quote(pattern)}/i)
      result1 = xs.select {|x| x.name_match?(re1) }
      return [] if result1.empty?
      return result1 if result1.size == 1
      re2 = (cache[1] ||= /\A#{Regexp.quote(pattern)}/)
      result2 = result1.select {|x| x.name_match?(re2) }
      return result1 if result2.empty?
      return result2 if result2.size == 1
      result3 = result2.select {|x| x.name?(pattern) }
      return result2 if result3.empty?
      return result3 if result3.size == 1   # no mean
      result3
    end

    def objectify(db, cs, records)
      records.each do |rec|
        rec.entry = db.get_method(MethodSpec.parse(rec.name))
      end
      SearchResult.new(db, self, cs, records)
    end

    def unify(ents)
      h = {}
      ents.each do |ent|
        if ent0 = h[ent]
          ent0.merge ent
        else
          h[ent] = ent
        end
      end
      h.values
    end

    def search_methods_in(c, type)
      case type
      when '.'
        search_tbl(c, c.smap)
      when '#'
        search_tbl(c, c.imap)
      when '.#'
        search_tbl(c, c.smap)
      when '::'
        search_tbl(c, c.cmap)
      when '$'
        return [] unless c.name == 'Kernel'
        search_svars(c)
      when nil
        search_tbl(c, c.smap) + search_tbl(c, c.imap)
      else
        raise "must not happen: #{pattern.type.inspect}"
      end
    end

    def search_tbl(c, tbl)
      m = tbl[@method]
      return [SearchResult::Record.new(c, m)] if m
      select_names(tbl.keys, @method, @mrecache)\
          .map {|name| SearchResult::Record.new(c, tbl[name]) }
    end

    def select_names(names, pattern, cache)
      re1 = (cache[0] ||= /\A#{Regexp.quote(pattern)}/i)
      result1 = names.select {|name| re1 =~ name }
      return []      if result1.empty?
      return result1 if result1.size == 1
      re2 = (cache[1] ||= /\A#{Regexp.quote(pattern)}\z/i)
      result2 = names.select {|name| re2 =~ name }
      return result1 if result2.empty?
      return result2 if result2.size == 1   # no mean
      result2
    end

  end


  class SearchResult

    def initialize(db, pattern, classes, records)
      @database = db
      @pattern = pattern
      @classes = classes
      @records = records
    end

    attr_reader :database
    attr_reader :pattern
    attr_reader :classes
    attr_reader :records

    def fail?
      @records.empty?
    end

    def success?
      not @records.empty?
    end

    def determined?
      @records.size == 1
    end

    def name
      @records.first.name
    end

    def names
      @records.map {|rec| rec.name }
    end

    def record
      @records.first
    end

    class Record
      def initialize(c, name)
        @org = [c]
        @name = name
        @entry = nil
      end

      attr_reader :org
      attr_reader :name
      attr_accessor :entry

      def ==(other)
        @name == other.name
      end

      alias eql? ==

      def hash
        @name.hash
      end

      def <=>(other)
        @entry <=> other.entry
      end

      def merge(other)
        @org |= other.org
      end

      def original_class
        # FIXME
        @org.first
      end
    end

  end

end

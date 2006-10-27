#
# bitclust/methodnamepattern.rb
#
# Copyright (c) 2006 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

require 'bitclust/methodid'

module BitClust

  # A MethodNamePattern has #klass, #type, #method and #library.
  # All attributes are string.
  # All attributes are optional.
  class MethodNamePattern

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

    def select_classes(cs)
      return cs unless @klass
      expand_ic(cs, @klass, @crecache)
    end

    # internal use only
    def _search_methods(db)
      if @type == '$'
        return search_svars(db.fetch_class('Kernel'))
      end
      recordclass = SearchResult::Record
      case
      when (@klass and @method)
        cs = select_classes(db.classes)
        return SearchResult.empty(db, self) if cs.empty?
        names = expand_name_wide(db._method_index.keys, @method, @mrecache)
        if @type
          records = cs.map {|c| search_methods_in(c, @type, names) }.flatten
        else
          ((/\A[A-Z]/ =~ @method) ? ['::', nil] : [nil, '::']).each do |t|
            records = cs.map {|c| search_methods_in(c, t, names) }.flatten
            break unless records.empty?
          end
        end
        SearchResult.new(db, self, cs, unify(squeeze(records, @method)))
      when @klass
        cs = select_classes(db.classes)
        return SearchResult.empty(db, self) if cs.empty?
        records = cs.map {|c|
          c.entries.map {|m|
            s = m.spec
            recordclass.new(s, s, m)
          }
        }.flatten
        SearchResult.new(db, self, cs, records)
      when @method
        mindex = db._method_index
        names = expand_name_narrow(mindex.keys, @method, @mrecache)
        classes = names.map {|name| mindex[name] }.flatten.uniq
        records = names.map {|name|
          spec = MethodSpec.new(nil, @type, name)
          mindex[name].map {|c|
            c.get_methods(spec).map {|m|
              recordclass.new(MethodSpec.new(c.name, m.typemark, name), m.spec, m)
            }
          }
        }.flatten
        SearchResult.new(db, self, classes, records)
      else
        SearchResult.new(db, self, db.classes,
            db.methods.map {|m| s = m.spec; recordclass.new(s, s, m) })
      end
    end

    private

    def search_svars(c)
      expand(c.special_variables, @method, @mrecache)
    end

    def squeeze(ents, pat)
      return ents if ents.size < 2
      result3 = ents.select {|ent| ent.method_name == pat }
      return result3 unless result3.empty?
      re = /\A#{Regexp.quote(pat)}\z/i
      result4 = ents.select {|ent| re =~ ent.method_name }
      return result4 unless result4.empty?
      ents
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

    def search_methods_in(c, type, names)
      case type
      when nil
        mlookup(c, '.', c._smap, names) + mlookup(c, '#', c._imap, names)
      when '.'
        mlookup(c, '.', c._smap, names)
      when '#'
        mlookup(c, '#', c._imap, names)
      when '.#'
        mlookup(c, '.', c._smap, names)
      when '::'
        mlookup(c, '::', c._cmap, names)
      when '$'
        return [] unless c.name == 'Kernel'
        search_svars(c).map {|m| SearchResult::Records.new(m.spec, m.spec, m) }
      else
        raise "must not happen: #{pattern.type.inspect}"
      end
    end

    def mlookup(c, type, tbl, names)
      recordclass = SearchResult::Record
      list = []
      names.each do |name|
        spec = tbl[name]
        list.push recordclass.new(MethodSpec.new(c.name, type, name),
                                  MethodSpec.parse(spec)) if spec
      end
      list
    end

    # Case-ignore search.  Optimized for constant search.
    def expand_ic(xs, pattern, cache)
      re1 = (cache[0] ||= /\A#{Regexp.quote(pattern)}/i)
      result1 = xs.select {|x| x.name_match?(re1) }
      return [] if result1.empty?
      return result1 if result1.size == 1
      re2 = (cache[1] ||= /\A#{Regexp.quote(pattern)}\z/i)
      result2 = result1.select {|x| x.name_match?(re2) }
      return result1 if result2.empty?
      return result2 if result2.size == 1   # no mean
      result2
    end

    def expand(xs, pattern, cache)
      re1 = (cache[0] ||= /\A#{Regexp.quote(pattern)}/i)
      result1 = xs.select {|x| x.name_match?(re1) }
      return [] if result1.empty?
      return result1 if result1.size == 1
      re2 = (cache[1] ||= /\A#{Regexp.quote(pattern)}\z/i)
      result2 = result1.select {|x| x.name_match?(re2) }
      return result1 if result2.empty?
      return result2 if result2.size == 1
      result3 = result2.select {|x| x.name?(pattern) }
      return result2 if result3.empty?
      return result3 if result3.size == 1   # no mean
      result3
    end

    # list up all candidates (no squeezing)
    def expand_name_wide(names, pattern, cache)
      re1 = (cache[0] ||= /\A#{Regexp.quote(pattern)}/i)
      names.select {|name| re1 =~ name }
    end

    # list up candidates (already squeezed)
    def expand_name_narrow(names, pattern, cache)
      re1 = (cache[0] ||= /\A#{Regexp.quote(pattern)}/i)
      result1 = names.select {|name| re1 =~ name }
      return [] if result1.empty?
      return result1 if result1.size == 1
      re2 = (cache[1] ||= /\A#{Regexp.quote(pattern)}\z/i)
      result2 = result1.select {|name| re2 =~ name }
      return result1 if result2.empty?
      return result2 if result2.size == 1
      result3 = result2.select {|name| pattern == name }
      return result2 if result3.empty?
      return result3 if result3.size == 1   # no mean
      result3
    end

  end


  class SearchResult

    def SearchResult.empty(db, pattern)
      new(db, pattern, [], [])
    end

    def initialize(db, pattern, classes, records)
      @database = db
      @pattern = pattern
      @classes = classes
      @records = records
      @records.each do |rec|
        rec.db = db
      end
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
      @records.map {|rec| rec.names }.flatten
    end

    def record
      @records.first
    end

    class Record
      def initialize(spec, origin, entry = nil)
        @db = nil
        @specs = [spec]
        @origin = origin
        @idstring = origin.to_s
        @entry = entry
      end

      attr_writer :db
      attr_reader :specs
      attr_reader :origin
      attr_reader :idstring

      def entry
        @entry ||= @db.get_method(@origin)
      end

      def name
        @specs.first.to_s
      end

      def names
        @specs.map {|spec| spec.to_s }
      end

      def method_name
        @specs.first.method
      end

      def original_name
        @idstring
      end

      def ==(other)
        @idstring == other.idstring
      end

      alias eql? ==

      def hash
        @idstring.hash
      end

      def <=>(other)
        entry() <=> other.entry
      end

      def merge(other)
        @specs |= other.specs
      end

      def inherited_method?
        not @specs.any? {|spec| spec.klass == @origin.klass }
      end
    end

  end

end

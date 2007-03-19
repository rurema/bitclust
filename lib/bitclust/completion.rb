#
# bitclust/completion.rb
#
# Copyright (c) 2006-2007 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the Ruby License.
#

require 'drb'

module BitClust

  module Completion

    private

    #
    # Completion Search
    #

    def _search_methods(pattern)
      case
      when pattern.empty?
        recordclass = SearchResult::Record
        SearchResult.new(self, pattern, classes(),
            methods().map {|m| s = m.spec; recordclass.new(s, s, m) })
      when pattern.special_variable?
        c = fetch_class('Kernel')
        SearchResult.new(self, pattern, [c], search_svars(c))
      when pattern.class?
        search_classes0(pattern)
      when pattern.method?
        case
        when pattern.klass && pattern.method
          search_methods_from_cname_mname(pattern)
        when pattern.method
          search_methods_from_mname(pattern)
        when pattern.type
          raise 'type only search is not supportted yet'
        else
          raise 'must not happen'
        end
      else
        raise 'must not happen'
      end
    end

    def search_svars(c)
      expand(c.special_variables, pattern.method, [])\
          .map {|m| SearchResult::Record.new(m.spec, m.spec, m) }
    end

    def search_classes0(pattern)
      cs = expand_ic(cs, pattern.klass, [])
      return SearchResult.empty(self, pattern) if cs.empty?
      recordclass = SearchResult::Record
      records = cs.map {|c|
        c.entries.map {|m|
          s = m.spec
          recordclass.new(s, s, m)
        }
      }.flatten
      SearchResult.new(self, pattern, cs, records)
    end

    def search_methods_from_mname(pattern)
      recordclass = SearchResult::Record
      names = expand_name_narrow(method_names(), pattern.method, [])
      records = names.map {|name|
        spec = MethodSpec.new(nil, pattern.type, name)
        mname2cids(name).map {|cid|
          c = fetch_class_id(cid)
          c.get_methods(spec).map {|m|
            recordclass.new(MethodSpec.new(c.name, m.typemark, name), m.spec, m)
          }
        }
      }.flatten
      SearchResult.new(self, pattern, [], records)
    end

    def search_methods_from_cname_mname(pat)
#timer_init
      names = expand_name_wide(method_names(), pat.method, [])
      return SearchResult.empty(self, pat) if names.empty?
#split_time "method expand (#{names.size})"
      pairs = make_cm_combination(pat.klass, names)
      return SearchResult.empty(self, pat) if pairs.empty?
#split_time "class  expand (#{pairs.size}c x #{$cm_comb_cnt}m -> #{mcnt(pairs)})"
      recs = try(types(pat.type,pat.method)) {|t| narrow_down_by_type(pairs,t) }
#split_time "type   expand (#{recs.size})"
      urecs = unify(squeeze(recs, pat.method))
#split_time "unify         (#{urecs.size})"
      SearchResult.new(self, pat, pairs.map {|c, ms| c }, urecs)
    end

    def timer_init
      @ts = [Time.now]
    end

    def split_time(msg)
      @ts.push Time.now
      $stderr.puts "#{@ts.size - 1}: #{'%.3f' % (@ts[-1] - @ts[-2])}: #{msg}"
    end

    def mcnt(pairs)
      pairs.map {|c, ms| ms.size }.inject(0) {|sum, n| sum + n }
    end

    def make_cm_combination(cpat, mnames)
      h = {}
      cnt = 0
      mnames.each do |m|
        cnames = expand_name_narrow(mname2cids_full(m), cpat, [])
        next if cnames.empty?
        cnt += 1
        cnames.each do |c|
          (h[c] ||= []).push m
        end
      end
$cm_comb_cnt = cnt
      h.to_a
    end

    def try(candidates)
      candidates.each do |c|
        result = yield c
        return result unless result.empty?
      end
      []
    end

    def types(type, mpattern)
      if type                     then [type == '.#' ? ['.', '#'] : [type]]
      elsif /\A[A-Z]/ =~ mpattern then [['::'], ['.', '#']]
      else                             [['.', '#'], ['::']]
      end
    end

    def narrow_down_by_type(pairs, ts)
      recordclass = SearchResult::Record
      result = []
      pairs.each do |cname, mnames|
        c = fetch_class(cname)
        ts.each do |t|
          mnames.each do |mname|
            if spec = c.match_entry(t, mname)
              result.push recordclass.new(MethodSpec.new(cname, t, mname),
                                          MethodSpec.parse(spec))
            end
          end
        end
      end
      result
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

    # Case-insensitive search.  Optimized for constant search.
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

    # list up all matched items (without squeezing)
    def expand_name_wide(names, pattern, cache)
      re1 = (cache[0] ||= /\A#{Regexp.quote(pattern)}/i)
      names.select {|name| re1 =~ name }
    end

    # list up matched items (with squeezing)
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

    #
    # Index
    #

    def save_completion_index
      save_class_index
      save_method_index
    end

    def intern_classname(name)
      intern_table()[name]
    end

    def intern_table
      @intern_table ||= 
          begin
            h = {}
            classnametable().each do |id, names|
              names.each do |n|
                h[n] = id
              end
            end
            h
          end
    end

    def save_class_index
      atomic_write_open('class/=index') {|f|
        classes().each do |c|
          #f.puts "#{c.id}\t#{c.names.join(' ')}"  # FIXME: support class alias
          f.puts "#{c.id}\t#{c.name}"
        end
      }
    end

    def classnametable
      @classnametable ||=
          begin
            h = {}
            foreach_line('class/=index') do |line|
              id, *names = *line.split
              h[id] = names
            end
            h
          rescue Errno::ENOENT
            {}
          end
    end

    def save_method_index
      index = make_method_index()
      atomic_write_open('method/=index') {|f|
        index.keys.sort.each do |name|
          f.puts "#{name}\t#{index[name].join(' ')}"
        end
      }
    end

    def make_method_index
      h = {}
      classes().each do |c|
        (c._imap.keys + c._smap.keys + c._cmap.keys).uniq.each do |name|
          (h[name] ||= []).push c.id
        end
      end
      h
    end

    def method_names
      @mnames ||= (@mindex0 ||= read_method_index()).keys
    end

    def mname2cids(name)
      (@mindex ||= {})[name] ||=
          begin
            h = (@mindex0 ||= read_method_index())
            cs = h[name]
            cs ? cs.split(nil) : nil
          end
    end

    def mname2cids_full(name)
      tbl = classnametable()
      mname2cids(name).map {|id| tbl[id] }.flatten
    end

    def read_method_index
      h = {}
      foreach_line('method/=index') do |line|
        name, cnames = line.split(nil, 2)
        h[name] = cnames
      end
      h
    end

  end


  class SearchResult

    include DRb::DRbUndumped

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

    def each_record(&block)
      @records.sort.each(&block)
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
        names().first
      end

      def names
        @specs.map {|spec| spec.display_name }
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

class Object
  def _remote_object?
    false
  end
end

class DRb::DRbObject
  def _remote_object?
    true
  end
end
